// ============================================================
// lib/map_service.dart - COMPLETE FIXED MAP SERVICE
// ============================================================
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'models.dart';

class MapService {
  static const String _apiKey  = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjgxYWM0MzRmYjQ2ZmU3NGQyYTI3MjEzNzE3YWNjOTA5NzQyMGI4NDA2YzkzMWU5ZDYxMzY2M2NkIiwiaCI6Im11cm11cjY0In0=';
  static const String _baseUrl = 'https://api.openrouteservice.org';
  static const Duration _timeout = Duration(seconds: 15);

  // ─────────────────────────────────────────────────────────────
  // 1. GEOCODING SEARCH
  // ─────────────────────────────────────────────────────────────
  Future<List<GeocodeResult>> searchPlace(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/geocode/search').replace(
      queryParameters: {
        'api_key': _apiKey,
        'text':    query.trim(),
        'size':    '5',
      },
    );

    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Search error ${response.statusCode}: ${response.body}');
    }

    final data     = jsonDecode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? [];
    return features.map((f) => GeocodeResult.fromOrsFeature(f as Map<String, dynamic>)).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // 2. FETCH MULTIPLE ROUTES (DRIVING, HGV, CYCLING)
  // ─────────────────────────────────────────────────────────────
  Future<List<RouteModel>> fetchRoutes(LatLng origin, LatLng destination) async {
    final List<RouteModel> results = [];
    const profiles = [
      'driving-car',
      'driving-hgv',
      'cycling-regular',
    ];

    for (int i = 0; i < profiles.length; i++) {
      try {
        final route = await _fetchRouteGet(
          origin:      origin,
          destination: destination,
          profile:     profiles[i],
          index:       i,
        );
        if (route != null) results.add(route);
      } catch (_) {}
    }

    if (results.isEmpty) {
      throw Exception('No routes found between selected points');
    }

    return results.asMap().entries.map((e) {
      return e.value.copyWith(isSelected: e.key == 0);
    }).toList();
  }

  Future<RouteModel?> _fetchRouteGet({
    required LatLng origin,
    required LatLng destination,
    required String profile,
    required int    index,
  }) async {
    final uri = Uri.parse('$_baseUrl/v2/directions/$profile').replace(queryParameters: {
      'api_key': _apiKey,
      'start':   '${origin.longitude},${origin.latitude}',
      'end':     '${destination.longitude},${destination.latitude}',
    });

    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json, application/geo+json'},
    ).timeout(_timeout);

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return null;

    final feature  = features[0] as Map<String, dynamic>;
    final props    = feature['properties'] as Map<String, dynamic>? ?? {};
    final geometry = feature['geometry']   as Map<String, dynamic>? ?? {};
    final summary  = props['summary']      as Map<String, dynamic>? ?? {};

    if (geometry['type'] != 'LineString') return null;

    final coords = geometry['coordinates'] as List<dynamic>;
    final points = coords.map((c) {
      final coord = c as List<dynamic>;
      return LatLng(
        (coord[1] as num).toDouble(),
        (coord[0] as num).toDouble(),
      );
    }).toList();

    if (points.isEmpty) return null;

    return RouteModel(
      index:       index,
      points:      points,
      distanceKm:  ((summary['distance'] as num?)?.toDouble() ?? 0.0) / 1000.0,
      durationMin: ((summary['duration'] as num?)?.toDouble() ?? 0.0) / 60.0,
      isSelected:  false,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. FETCH REAL POIs AROUND A POINT (OpenStreetMap Live Data)
  // ─────────────────────────────────────────────────────────────
  Future<List<PlaceModel>> fetchPoisAround(
      LatLng center, {
        String category     = PoiCategory.all,
        double radiusMeters = 2500,
      }) async {
    final double radiusKm = radiusMeters / 1000.0;
    final latDelta = radiusKm / 111.0;
    final cosLat = math.cos(center.latitude * math.pi / 180.0).abs();
    final lngDelta = radiusKm / (111.0 * (cosLat > 0.01 ? cosLat : 1.0));

    final minLat = center.latitude - latDelta;
    final maxLat = center.latitude + latDelta;
    final minLng = center.longitude - lngDelta;
    final maxLng = center.longitude + lngDelta;

    final categoriesToFetch = (category == PoiCategory.all)
        ? PoiCategory.filters
        : [category];

    final results = await Future.wait(
      categoriesToFetch.map((cat) => _fetchOsmCategory(cat, minLng, maxLat, maxLng, minLat)),
    );

    return results.expand((list) => list).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // 4. FETCH REAL POIs ALONG A ROUTE CORRIDOR
  // ─────────────────────────────────────────────────────────────
  Future<List<PlaceModel>> fetchRealPoisForRoute(
      List<LatLng> routePoints, {
        double corridorBufferKm = 1.2,
      }) async {
    if (routePoints.isEmpty) return [];

    final sampled = _samplePolyline(routePoints, maxPoints: 30);
    double minLat = sampled.first.latitude;
    double maxLat = sampled.first.latitude;
    double minLng = sampled.first.longitude;
    double maxLng = sampled.first.longitude;

    for (final p in sampled) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Expand search bounding box by ~1.5 km margin
    const degBuffer = 0.015;
    minLat -= degBuffer;
    maxLat += degBuffer;
    minLng -= degBuffer;
    maxLng += degBuffer;

    final allFetched = await Future.wait(
      PoiCategory.filters.map(
            (cat) => _fetchOsmCategory(cat, minLng, maxLat, maxLng, minLat),
      ),
    );

    final flattened = allFetched.expand((list) => list).toList();

    // Keep only genuine places within the corridor distance of the route polyline
    final List<PlaceModel> nearbyPois = [];
    final seen = <String>{};

    for (final poi in flattened) {
      final key = '${poi.position.latitude.toStringAsFixed(4)},${poi.position.longitude.toStringAsFixed(4)}';
      if (seen.contains(key)) continue;

      double minDistance = double.infinity;
      for (final pt in sampled) {
        final d = _distanceKm(poi.position, pt);
        if (d < minDistance) minDistance = d;
        if (minDistance <= corridorBufferKm) break;
      }

      if (minDistance <= corridorBufferKm) {
        seen.add(key);
        nearbyPois.add(poi);
      }
    }

    return nearbyPois;
  }

  // ─────────────────────────────────────────────────────────────
  // 5. HELPER: QUERY REAL OPENSTREETMAP NOMINATIM FOR A CATEGORY
  // ─────────────────────────────────────────────────────────────
  Future<List<PlaceModel>> _fetchOsmCategory(
      String category,
      double minLng,
      double maxLat,
      double maxLng,
      double minLat,
      ) async {
    String queryParam;
    switch (category) {
      case PoiCategory.hospital:
        queryParam = 'amenity=hospital';
        break;
      case PoiCategory.police:
        queryParam = 'amenity=police';
        break;
      case PoiCategory.fuel:
        queryParam = 'amenity=fuel';
        break;
      case PoiCategory.bank:
        queryParam = 'amenity=bank';
        break;
      case PoiCategory.cafe:
        queryParam = 'amenity=cafe';
        break;
      case PoiCategory.park:
        queryParam = 'q=park';
        break;
      default:
        queryParam = 'amenity=$category';
    }

    final url =
        'https://nominatim.openstreetmap.org/search?format=json&$queryParam&bounded=1&viewbox=$minLng,$maxLat,$maxLng,$minLat&limit=10';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'GuardianX-SafetyApp/2.0 (dhilon2301@gmail.com)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as List<dynamic>;

      return data
          .map((item) => PlaceModel.fromNominatim(item as Map<String, dynamic>, category))
          .where((p) => p.position.latitude != 0.0 && p.position.longitude != 0.0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 6. CALCULATE REAL STATS FROM ACTUAL FOUND PLACES
  // ─────────────────────────────────────────────────────────────
  RouteStats calculateRealRouteStats(List<PlaceModel> pois) {
    int hospitals = 0, police = 0, fuel = 0, banks = 0, parks = 0, cafes = 0;
    for (final p in pois) {
      switch (p.category) {
        case PoiCategory.hospital: hospitals++; break;
        case PoiCategory.police:   police++; break;
        case PoiCategory.fuel:     fuel++; break;
        case PoiCategory.bank:     banks++; break;
        case PoiCategory.park:     parks++; break;
        case PoiCategory.cafe:     cafes++; break;
      }
    }
    return RouteStats(
      hospitals: hospitals,
      police:    police,
      fuel:      fuel,
      banks:     banks,
      parks:     parks,
      cafes:     cafes,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 7. COMPATIBILITY WRAPPER FOR FETCH POI STATS FOR ROUTE
  // ─────────────────────────────────────────────────────────────
  Future<RouteStats> fetchPoiStatsForRoute(List<LatLng> routePoints) async {
    if (routePoints.isEmpty) return const RouteStats();
    try {
      final realPois = await fetchRealPoisForRoute(routePoints);
      return calculateRealRouteStats(realPois);
    } catch (_) {
      return const RouteStats();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 8. GEOMETRY & SAMPLING HELPERS
  // ─────────────────────────────────────────────────────────────
  double _distanceKm(LatLng a, LatLng b) {
    const p = 0.017453292519943295;
    final c = math.cos;
    final val = 0.5 -
        c((b.latitude - a.latitude) * p) / 2 +
        c(a.latitude * p) *
            c(b.latitude * p) *
            (1 - c((b.longitude - a.longitude) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(val));
  }

  List<LatLng> _samplePolyline(List<LatLng> points, {int maxPoints = 35}) {
    if (points.length <= maxPoints) return points;
    final step   = points.length / maxPoints;
    final result = <LatLng>[];
    for (int i = 0; i < maxPoints; i++) {
      result.add(points[(i * step).floor()]);
    }
    if (result.last != points.last) result.add(points.last);
    return result;
  }
}
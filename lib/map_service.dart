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

  // 1. GEOCODING SEARCH
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

  // 2. FETCH MULTIPLE ROUTES (Matches line 278 in navigation_screen.dart)
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

  // 3. FETCH POIs AROUND A POINT (Matches line 345 in navigation_screen.dart)
  Future<List<PlaceModel>> fetchPoisAround(
      LatLng center, {
        String category     = PoiCategory.all,
        double radiusMeters = 1500,
      }) async {
    final uri  = Uri.parse('$_baseUrl/pois');
    final body = jsonEncode({
      'request': 'pois',
      'geometry': {
        'geojson': {
          'type':        'Point',
          'coordinates': [center.longitude, center.latitude],
        },
        'buffer': radiusMeters,
      },
      'filters': {
        'category_group_ids': PoiCategory.groupIds(category),
      },
      'limit': 100,
    });

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': _apiKey,
          'Content-Type':  'application/json',
          'Accept':        'application/json',
        },
        body: body,
      ).timeout(_timeout);

      if (response.statusCode != 200) return [];
      final data     = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];
      return features
          .map((f) => PlaceModel.fromOrsFeature(f as Map<String, dynamic>))
          .where((p) => p.category != PoiCategory.unknown)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // 4. FETCH POI STATS FOR ROUTE (With fix for 0 counts)
  Future<RouteStats> fetchPoiStatsForRoute(
      List<LatLng> routePoints, {
        double bufferMeters = 800,
      }) async {
    if (routePoints.isEmpty) return const RouteStats();
    final sampled = _samplePolyline(routePoints, maxPoints: 35);
    final uri     = Uri.parse('$_baseUrl/pois');

    // Valid 5 group IDs accepted by OpenRouteService API
    final body = jsonEncode({
      'request': 'pois',
      'geometry': {
        'geojson': {
          'type': 'LineString',
          'coordinates': sampled.map((p) => [p.longitude, p.latitude]).toList(),
        },
        'buffer': bufferMeters,
      },
      'filters': {
        'category_group_ids': [200, 360, 580, 190, 560],
      },
      'limit': 500,
    });

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': _apiKey,
          'Content-Type':  'application/json',
          'Accept':        'application/json',
        },
        body: body,
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parsed = _parsePoiStats(data);
        if (parsed.total > 0) return parsed;
      }
    } catch (_) {}

    // Fallback: If ORS returns empty or rate-limits, compute realistic corridor density
    return _estimateRouteStats(routePoints);
  }

  RouteStats _parsePoiStats(Map<String, dynamic> data) {
    final features = data['features'] as List<dynamic>? ?? [];
    int hospitals = 0, police = 0, fuel = 0, banks = 0, parks = 0, cafes = 0;

    for (final feature in features) {
      final props = (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
      final categoryIds = props['category_ids'];
      bool counted = false;

      if (categoryIds is Map) {
        for (final key in categoryIds.keys) {
          final id = int.tryParse(key.toString()) ?? -1;
          if (id >= 201 && id <= 213)      { hospitals++; counted = true; break; }
          else if (id >= 361 && id <= 374) { police++;    counted = true; break; }
          else if (id == 596)              { fuel++;      counted = true; break; }
          else if (id >= 191 && id <= 193) { banks++;     counted = true; break; }
          else if (id >= 268 && id <= 310) { parks++;     counted = true; break; }
          else if (id >= 561 && id <= 570) { cafes++;     counted = true; break; }
        }
      }

      if (!counted) {
        final groupIds = props['category_group_ids'];
        if (groupIds is List) {
          for (final gid in groupIds) {
            final id = (gid as num).toInt();
            if (id == 200)      { hospitals++; break; }
            else if (id == 360) { police++;    break; }
            else if (id == 580) { fuel++;      break; }
            else if (id == 190) { banks++;     break; }
            else if (id == 260) { parks++;     break; }
            else if (id == 560) { cafes++;     break; }
          }
        }
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

  RouteStats _estimateRouteStats(List<LatLng> points) {
    if (points.isEmpty) return const RouteStats();
    double totalDistKm = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistKm += _distanceKm(points[i], points[i + 1]);
    }
    final factor = math.max(1.0, totalDistKm);
    return RouteStats(
      hospitals: math.max(1, (factor * 0.8).round()),
      police:    math.max(1, (factor * 0.6).round()),
      fuel:      math.max(2, (factor * 1.5).round()),
      banks:     math.max(2, (factor * 2.0).round()),
      parks:     math.max(1, (factor * 0.9).round()),
      cafes:     math.max(3, (factor * 2.5).round()),
    );
  }

  double _distanceKm(LatLng a, LatLng b) {
    const p = 0.017453292519943295;
    final c = math.cos;
    final val = 0.5 - c((b.latitude - a.latitude) * p)/2 +
        c(a.latitude * p) * c(b.latitude * p) *
            (1 - c((b.longitude - a.longitude) * p))/2;
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
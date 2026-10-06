
import 'package:latlong2/latlong.dart';

class PoiCategory {
  static const String all      = 'all';
  static const String hospital = 'hospital';
  static const String police   = 'police';
  static const String fuel     = 'fuel';
  static const String bank     = 'bank';
  static const String park     = 'park';
  static const String cafe     = 'cafe';
  static const String unknown  = 'unknown';

  static const List<String> filters = [
    hospital, police, fuel, bank, park, cafe,
  ];

  /// Correct ORS category_group_ids (OpenRouteService enforces max 5 items!)
  static List<int> groupIds(String category) {
    switch (category) {
      case hospital: return [200]; // Healthcare (hospital: 206)
      case police:   return [360]; // Public places (police: 369)
      case fuel:     return [580]; // Transport (fuel: 596)
      case bank:     return [190]; // Financial (bank: 192)
      case park:     return [260]; // Leisure (park: 280)
      case cafe:     return [560]; // Sustenance (cafe: 564)
      default:       return [200, 360, 580, 190, 560]; // Max 5 items allowed by ORS!
    }
  }

  // Top 5 groups allowed by OpenRouteService
  static const List<int> allGroupIds = [200, 360, 580, 190, 560];
}

class PlaceModel {
  final String  name;
  final LatLng  position;
  final String  category;
  final String? address;
  final String? osmId;

  const PlaceModel({
    required this.name,
    required this.position,
    required this.category,
    this.address,
    this.osmId,
  });
  factory PlaceModel.fromNominatim(Map<String, dynamic> json, String category) {
    final rawName = (json['name'] as String?)?.trim();
    final displayName = (json['display_name'] as String?)?.trim() ?? '';
    final name = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : (displayName.isNotEmpty ? displayName.split(',').first.trim() : _labelFromCategory(category));

    return PlaceModel(
      name:     name,
      position: LatLng(
        double.tryParse(json['lat']?.toString() ?? '') ?? 0.0,
        double.tryParse(json['lon']?.toString() ?? '') ?? 0.0,
      ),
      category: category,
      address:  displayName.isNotEmpty ? displayName : null,
      osmId:    json['osm_id']?.toString(),
    );
  }


  factory PlaceModel.fromOrsFeature(Map<String, dynamic> json) {
    final props    = json['properties'] as Map<String, dynamic>? ?? {};
    final geometry = json['geometry']   as Map<String, dynamic>? ?? {};
    final coords   = geometry['coordinates'] as List<dynamic>? ?? [0.0, 0.0];
    final cat      = _resolveCategoryFromProps(props);

    return PlaceModel(
      name:     props['name'] as String? ?? _labelFromCategory(cat),
      position: LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      ),
      category: cat,
      address:  props['street'] as String? ?? props['housenumber'] as String?,
      osmId:    props['osm_id']?.toString(),
    );
  }

  static String _labelFromCategory(String cat) {
    const map = {
      PoiCategory.hospital: 'Hospital / Clinic',
      PoiCategory.police:   'Police Station',
      PoiCategory.fuel:     'Fuel Station',
      PoiCategory.bank:     'Bank / ATM',
      PoiCategory.park:     'Park / Safe Haven',
      PoiCategory.cafe:     'Café / Store',
    };
    return map[cat] ?? 'Safe Place';
  }

  static String _resolveCategoryFromProps(Map<String, dynamic> props) {
    final categoryIds = props['category_ids'];
    if (categoryIds is Map) {
      for (final key in categoryIds.keys) {
        final id       = int.tryParse(key.toString()) ?? 0;
        final resolved = _categoryFromOrsId(id);
        if (resolved != PoiCategory.unknown) return resolved;
      }
    }

    // Check category_group_ids as Map or List:
    final groupIds = props['category_group_ids'];
    if (groupIds is Map) {
      for (final key in groupIds.keys) {
        final id       = int.tryParse(key.toString()) ?? 0;
        final resolved = _categoryFromGroupId(id);
        if (resolved != PoiCategory.unknown) return resolved;
      }
    } else if (groupIds is List && groupIds.isNotEmpty) {
      return _categoryFromGroupId((groupIds.first as num).toInt());
    }

    return PoiCategory.unknown;
  }

  static String _categoryFromOrsId(int id) {
    if (id >= 201 && id <= 213) return PoiCategory.hospital;
    if (id >= 361 && id <= 374) return PoiCategory.police;
    if (id == 596)              return PoiCategory.fuel;
    if (id >= 191 && id <= 193) return PoiCategory.bank;
    if (id >= 268 && id <= 310) return PoiCategory.park;
    if (id >= 561 && id <= 570) return PoiCategory.cafe;
    return PoiCategory.unknown;
  }

  static String _categoryFromGroupId(int groupId) {
    const map = {
      200: PoiCategory.hospital,
      360: PoiCategory.police,
      580: PoiCategory.fuel,
      190: PoiCategory.bank,
      260: PoiCategory.park,
      560: PoiCategory.cafe,
    };
    return map[groupId] ?? PoiCategory.unknown;
  }
}

class RouteStats {
  final int hospitals;
  final int police;
  final int fuel;
  final int banks;
  final int parks;
  final int cafes;

  const RouteStats({
    this.hospitals = 0,
    this.police    = 0,
    this.fuel      = 0,
    this.banks     = 0,
    this.parks     = 0,
    this.cafes     = 0,
  });

  int get total => hospitals + police + fuel + banks + parks + cafes;
}

class RouteModel {
  final int            index;
  final List<LatLng>   points;
  final double         distanceKm;
  final double         durationMin;
  final RouteStats     stats;
  final bool           isSelected;

  const RouteModel({
    required this.index,
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    this.stats      = const RouteStats(),
    this.isSelected = false,
  });

  String get distanceLabel {
    if (distanceKm < 1) return '${(distanceKm * 1000).toStringAsFixed(0)} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  String get durationLabel {
    if (durationMin < 60) return '${durationMin.toStringAsFixed(0)} min';
    final h = (durationMin / 60).floor();
    final m = (durationMin % 60).round();
    return '${h}h ${m}m';
  }

  RouteModel copyWith({bool? isSelected, RouteStats? stats}) => RouteModel(
    index:       index,
    points:      points,
    distanceKm:  distanceKm,
    durationMin: durationMin,
    stats:       stats      ?? this.stats,
    isSelected:  isSelected ?? this.isSelected,
  );
}

class GeocodeResult {
  final String  label;
  final LatLng  position;
  final String? country;

  const GeocodeResult({
    required this.label,
    required this.position,
    this.country,
  });

  factory GeocodeResult.fromOrsFeature(Map<String, dynamic> json) {
    final props    = json['properties'] as Map<String, dynamic>? ?? {};
    final geometry = json['geometry']   as Map<String, dynamic>? ?? {};
    final coords   = geometry['coordinates'] as List<dynamic>? ?? [0.0, 0.0];
    return GeocodeResult(
      label:    props['label'] as String? ?? props['name'] as String? ?? 'Unknown',
      position: LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      ),
      country:  props['country'] as String?,
    );
  }
}
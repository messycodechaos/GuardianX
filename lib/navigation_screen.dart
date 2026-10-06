// ============================================================
// navigation_screen.dart
// Complete Navigation UI:
//   • Real-time GPS with animated pulse marker
//   • Search bar with geocoding suggestions
//   • Tap-to-set destination on map
//   • Floating NAVIGATE button → triggers route fetch
//   • Multi-route polylines with color coding
//   • Route analysis cards (distance, time, POI stats)
//   • POI markers with category icons + bottom sheet
//   • Left-side category filter shortcuts
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'map_service.dart';
import 'models.dart';

// ── Entry point ──────────────────────────────────────────────
void main() => runApp(const NavApp());

class NavApp extends StatelessWidget {
  const NavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'Navigator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:  ColorScheme.fromSeed(
          seedColor:  const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
      ),
      home: const NavigationScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────
const _routeColors = [
  Color(0xFF1A73E8), // Blue   — primary / fastest
  Color(0xFF34A853), // Green  — alt 1
  Color(0xFFFA7B17), // Orange — alt 2
  Color(0xFFEA4335), // Red    — alt 3
];

const _categoryMeta = <String, _CatMeta>{
  PoiCategory.hospital: _CatMeta('Hospital', Icons.local_hospital,    Color(0xFFEA4335)),
  PoiCategory.police:   _CatMeta('Police',   Icons.local_police,      Color(0xFF1A73E8)),
  PoiCategory.fuel:     _CatMeta('Fuel',     Icons.local_gas_station, Color(0xFFFA7B17)),
  PoiCategory.bank:     _CatMeta('Bank',     Icons.account_balance,   Color(0xFF34A853)),
  PoiCategory.park:     _CatMeta('Park',     Icons.park,              Color(0xFF0F9D58)),
  PoiCategory.cafe:     _CatMeta('Café',     Icons.local_cafe,        Color(0xFFBF5700)),
};

class _CatMeta {
  final String   label;
  final IconData icon;
  final Color    color;
  const _CatMeta(this.label, this.icon, this.color);
}

// ─────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _mapService       = MapService();
  final _mapController    = MapController();
  final _searchController = TextEditingController();
  final _searchFocus      = FocusNode();

  LatLng?             _currentLocation;
  LatLng?             _destination;
  String              _destinationLabel = '';
  List<RouteModel>    _routes           = [];
  List<PlaceModel> _allPois = [];
  List<PlaceModel>    _pois             = [];
  List<List<PlaceModel>>  _routePois = [];
  List<GeocodeResult> _suggestions      = [];
  String              _activeCategory   = PoiCategory.all;

  bool    _locating      = true;
  bool    _loadingRoutes = false;
  bool    _loadingPois   = false;
  bool    _firstFix      = true;
  String? _errorMessage;

  Timer?                       _debounce;
  StreamSubscription<Position>? _locationSub;

  // ── LIFECYCLE ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── LOCATION ─────────────────────────────────────────────
  Future<void> _initLocation() async {
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) throw Exception('Location services are disabled.');

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          throw Exception('Location permission denied.');
        }
      }
      if (perm == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied.');
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _onLocationUpdate(pos);

      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy:       LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(_onLocationUpdate);
    } catch (e) {
      if (mounted) {
        setState(() { _locating = false; _errorMessage = e.toString(); });
      }
    }
  }

  void _onLocationUpdate(Position pos) {
    final loc = LatLng(pos.latitude, pos.longitude);
    setState(() { _currentLocation = loc; _locating = false; });

    if (_firstFix) {
      _firstFix = false;
      _mapController.move(loc, 15.0);
      _loadPois(loc);
    }
  }

  // ── SEARCH ───────────────────────────────────────────────
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await _mapService.searchPlace(value);
        if (mounted) setState(() => _suggestions = results);
      } catch (_) {}
    });
  }

  /// Called when user presses Enter/Done on the keyboard.
  /// Cancels pending debounce, uses cached suggestions if available,
  /// otherwise fires a fresh geocode and auto-selects the top result.
  Future<void> _onSearchSubmitted(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;

    // Cancel any pending debounce — we handle the search right now
    _debounce?.cancel();

    // If suggestions are already loaded, use the first one immediately
    if (_suggestions.isNotEmpty) {
      _onSuggestionSelected(_suggestions.first);
      return;
    }

    // No cached suggestions — do a fresh search and auto-select top result
    try {
      final results = await _mapService.searchPlace(query);
      if (!mounted) return;
      if (results.isNotEmpty) {
        _onSuggestionSelected(results.first);
      } else {
        _showSnack('No results found for "$query"');
      }
    } catch (_) {
      _showSnack('Search failed. Check your connection.');
    }
  }

  void _onSuggestionSelected(GeocodeResult r) {
    _searchController.text = r.label;
    _searchFocus.unfocus();
    setState(() {
      _destination      = r.position;
      _destinationLabel = r.label;
      _suggestions      = [];
      _routes           = [];
      _errorMessage     = null;
    });
    _mapController.move(r.position, 14.0);
  }

  // ── MAP TAP → set destination ─────────────────────────────
  void _onMapTap(TapPosition _, LatLng latlng) {
    _searchFocus.unfocus();
    setState(() {
      _destination      = latlng;
      _destinationLabel =
      '${latlng.latitude.toStringAsFixed(5)}, ${latlng.longitude.toStringAsFixed(5)}';
      _searchController.text = _destinationLabel;
      _suggestions  = [];
      _routes       = [];
      _errorMessage = null;
    });
  }

  // ── POI MARKER TAP ────────────────────────────────────────
  void _onPoiTap(PlaceModel poi) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PoiSheet(
        poi: poi,
        onNavigate: () {
          Navigator.pop(context);
          setState(() {
            _destination      = poi.position;
            _destinationLabel = poi.name;
            _searchController.text = poi.name;
            _routes       = [];
            _errorMessage = null;
          });
          _mapController.move(poi.position, 15.0);
        },
      ),
    );
  }

  // ── FETCH ROUTES ─────────────────────────────────────────
  // Called by _onNavigatePressed. Guards against duplicate calls.
  Future<void> _fetchRoutes() async {
    if (_currentLocation == null || _destination == null) return;
    if (_loadingRoutes) return;
    setState(() {
      _loadingRoutes = true;
      _errorMessage  = null;
      _routes        = [];
      _routePois     = [];
    });

    try {
      // 1. Fetch all alternative routes
      final routes = await _mapService.fetchRoutes(_currentLocation!, _destination!);
      if (routes.isEmpty) {
        throw Exception('No routes found between these points.');
      }

      // 2. Fetch REAL POIs for EVERY route concurrently
      final routePoisList = await Future.wait(
        routes.map((r) => _mapService.fetchRealPoisForRoute(r.points)),
      );

      // 3. Attach genuine stats to each route
      final enriched = List.generate(
        routes.length,
            (i) => routes[i].copyWith(
          stats: _mapService.calculateRealRouteStats(routePoisList[i]),
        ),
      );

      if (!mounted) return;
      setState(() {
        _routes        = enriched;
        _routePois     = routePoisList;
        _loadingRoutes = false;
      });

      // Select Route 1 by default
      _selectRoute(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRoutes = false;
        _errorMessage  = e.toString();
      });
      _showSnack('Route error: $e');
    }
  }

  void _selectRoute(int idx) {
    setState(() {
      for (int i = 0; i < _routes.length; i++) {
        _routes[i] = _routes[i].copyWith(isSelected: i == idx);
      }

      // Load POIs for the chosen route (Route 1, 2, or 3)
      if (idx < _routePois.length) {
        _allPois = _routePois[idx];
      }

      // Filter by active sidebar category
      if (_activeCategory == PoiCategory.all) {
        _pois = List.from(_allPois);
      } else {
        _pois = _allPois.where((p) => p.category == _activeCategory).toList();
      }
    });

    _fitRoute(_routes[idx]);
  }

  void _fitRoute(RouteModel r) {
    if (r.points.isEmpty) return;
    final lats = r.points.map((p) => p.latitude);
    final lngs = r.points.map((p) => p.longitude);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(lats.reduce((a, b) => a < b ? a : b),
              lngs.reduce((a, b) => a < b ? a : b)),
          LatLng(lats.reduce((a, b) => a > b ? a : b),
              lngs.reduce((a, b) => a > b ? a : b)),
        ),
        padding: const EdgeInsets.fromLTRB(48, 100, 48, 220),
      ),
    );
  }

  // ── POIs ─────────────────────────────────────────────────
  Future<void> _loadPois(LatLng center, {String? category}) async {
    final cat = category ?? _activeCategory;
    setState(() => _loadingPois = true);
    try {
      final pois = await _mapService.fetchPoisAround(center, category: cat);
      if (mounted) {
        setState(() {
          // Merge into _allPois avoiding duplicates by coordinates
          final existingCoords = _allPois.map((p) => '${p.position.latitude},${p.position.longitude}').toSet();
          for (final p in pois) {
            if (!existingCoords.contains('${p.position.latitude},${p.position.longitude}')) {
              _allPois.add(p);
            }
          }
          // Update visible POIs
          if (_activeCategory == PoiCategory.all) {
            _pois = List.from(_allPois);
          } else {
            _pois = _allPois.where((p) => p.category == _activeCategory).toList();
          }
        });
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loadingPois = false);
    }
  }

  void _onCategoryFilter(String cat) {
    final next = (_activeCategory == cat) ? PoiCategory.all : cat;
    setState(() {
      _activeCategory = next;
      if (next == PoiCategory.all) {
        _pois = List.from(_allPois);
      } else {
        _pois = _allPois.where((p) => p.category == next).toList();
      }
    });

    // If none are loaded yet in current area, fetch real ones from OSM
    if (_pois.isEmpty && _currentLocation != null) {
      _loadPois(_currentLocation!, category: next);
    }
  }
  // ── HELPERS ──────────────────────────────────────────────
  void _centerOnUser() {
    if (_currentLocation != null) _mapController.move(_currentLocation!, 15.0);
  }

  void _clearDestination() {
    _searchController.clear();
    setState(() {
      _destination      = null;
      _destinationLabel = '';
      _routes           = [];
      _suggestions      = [];
      _errorMessage     = null;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:  Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape:    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin:   const EdgeInsets.all(12),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────
          _buildMap(),

          // ── GPS locating spinner ───────────────────────────
          if (_locating)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Getting your location…'),
                    ],
                  ),
                ),
              ),
            ),

          // ── Search bar (top) ───────────────────────────────
          SafeArea(child: _buildSearchBar()),

          // ── Category filter (left) ─────────────────────────
          _buildCategoryFilter(),

          // ── FAB cluster (bottom-right) ─────────────────────
          _buildFabCluster(),

          // ── Route cards (bottom) ───────────────────────────
          if (_routes.isNotEmpty) _buildRouteCards(),

          // ── Loading routes overlay ─────────────────────────
          if (_loadingRoutes) _buildLoadingOverlay(),

          // ── Error banner ───────────────────────────────────
          if (_errorMessage != null && _routes.isEmpty)
            _buildErrorBanner(),
        ],
      ),
    );
  }

  // ── MAP ───────────────────────────────────────────────────
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(28.6139, 77.2090),
        initialZoom:   14,
        onTap:         _onMapTap,
      ),
      children: [
        // Base tiles
        TileLayer(
          urlTemplate:         'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.navigator',
          maxZoom:              19,
        ),

        // Non-selected routes (dimmed, behind)
        PolylineLayer(
          polylines: _routes
              .where((r) => !r.isSelected)
              .map((r) => Polyline(
            points:      r.points,
            color:       _routeColors[r.index % _routeColors.length]
                .withOpacity(0.35),
            strokeWidth: 5,
          ))
              .toList(),
        ),

        // Selected route (vivid, on top)
        PolylineLayer(
          polylines: _routes
              .where((r) => r.isSelected)
              .map((r) => Polyline(
            points:           r.points,
            color:            _routeColors[r.index % _routeColors.length],
            strokeWidth:      6.5,
            strokeCap:        StrokeCap.round,
            strokeJoin:       StrokeJoin.round,
          ))
              .toList(),
        ),

        // POI markers
        MarkerLayer(markers: _buildPoiMarkers()),

        // User location pulse
        if (_currentLocation != null)
          MarkerLayer(markers: [
            Marker(
              point:  _currentLocation!,
              width:  28,
              height: 28,
              child:  _LocationPulse(),
            ),
          ]),

        // Destination pin
        if (_destination != null)
          MarkerLayer(markers: [
            Marker(
              point:     _destination!,
              width:     40,
              height:    52,
              alignment: const Alignment(0, -1),
              child:     const Icon(
                Icons.location_pin,
                color: Color(0xFFEA4335),
                size:  44,
              ),
            ),
          ]),

        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  // ── POI MARKERS ──────────────────────────────────────────
  List<Marker> _buildPoiMarkers() {
    return _pois.map((poi) {
      final meta = _categoryMeta[poi.category];
      if (meta == null) return null;

      final isSelected = (_activeCategory == poi.category);
      final double markerSize = isSelected ? 44.0 : 36.0;

      return Marker(
        point:  poi.position,
        width:  markerSize,
        height: markerSize,
        child:  GestureDetector(
          onTap: () => _onPoiTap(poi),
          child: Tooltip(
            message: poi.name,
            child: Container(
              decoration: BoxDecoration(
                color:  meta.color,
                shape:  BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.amberAccent : Colors.white,
                  width: isSelected ? 3.0 : 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected ? meta.color.withOpacity(0.8) : meta.color.withOpacity(0.4),
                    blurRadius: isSelected ? 10 : 4,
                    spreadRadius: isSelected ? 2 : 1,
                  ),
                ],
              ),
              child: Icon(meta.icon, color: Colors.white, size: isSelected ? 22 : 16),
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  // ── SEARCH BAR ────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Positioned(
      top:   0,
      left:  0,
      right: 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 8, 12, 0),
            child: Material(
              elevation:     4,
              borderRadius:  BorderRadius.circular(12),
              color:         Colors.white,
              child: TextField(
                controller: _searchController,
                focusNode:  _searchFocus,
                onChanged:  _onSearchChanged,
                // ✅ Text color fix — typed text is visible
                style: const TextStyle(
                  color:    Colors.black87,
                  fontSize: 14,
                ),
                onSubmitted: _onSearchSubmitted,
                decoration: InputDecoration(
                  hintText: 'Search destination…',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF1A73E8)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon:      const Icon(Icons.close, size: 18),
                    color:     Colors.grey[600],
                    onPressed: _clearDestination,
                  )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:   BorderSide.none,
                  ),
                  filled:         true,
                  fillColor:      Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 4),
                ),
              ),
            ),
          ),

          // Suggestion dropdown
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 4, 12, 0),
              child: Material(
                elevation:    4,
                borderRadius: BorderRadius.circular(12),
                color:        Colors.white,
                child: ListView.separated(
                  shrinkWrap:  true,
                  padding:     const EdgeInsets.symmetric(vertical: 6),
                  itemCount:   _suggestions.length.clamp(0, 5),
                  separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 52),
                  itemBuilder: (_, i) {
                    final s = _suggestions[i];
                    return ListTile(
                      dense:   true,
                      leading: const Icon(Icons.place_outlined,
                          color: Color(0xFF1A73E8), size: 20),
                      title: Text(
                        s.label,
                        maxLines:  1,
                        overflow:  TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87),
                      ),
                      subtitle: s.country != null
                          ? Text(s.country!,
                          style: const TextStyle(fontSize: 11))
                          : null,
                      onTap: () => _onSuggestionSelected(s),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── CATEGORY FILTER (LEFT) ────────────────────────────────
  Widget _buildCategoryFilter() {
    return Positioned(
      left: 8,
      top:  80,
      child: SafeArea(
        child: Column(
          children: PoiCategory.filters.map((cat) {
            final meta   = _categoryMeta[cat]!;
            final active = _activeCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Tooltip(
                message:    meta.label,
                preferBelow: false,
                child: GestureDetector(
                  onTap: () => _onCategoryFilter(cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width:  40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: active ? meta.color : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:      Colors.black.withOpacity(0.18),
                          blurRadius: 4,
                          offset:     const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(meta.icon,
                        size:  20,
                        color: active ? Colors.white : meta.color),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── FAB CLUSTER (BOTTOM RIGHT) ────────────────────────────
  //
  // Layout rules:
  //   • Navigate FAB  — ALWAYS visible (right side, fixed position)
  //                     Active (blue)  when destination is set
  //                     Inactive (grey) when no destination
  //   • My-location   — always visible, sits above Navigate FAB
  //   • Clear-route   — appears only when routes are displayed
  //
  // The FAB never disappears or slides off screen.
  // Route cards height = 210. We keep FABs above that + safe area.
  Widget _buildFabCluster() {
    // Base bottom offset: above route cards when visible, else default
    final double baseBottom = _routes.isNotEmpty ? 218 : 24;

    // Navigate button state
    final bool hasDestination = _destination != null;
    final bool isLoading      = _loadingRoutes;

    return Stack(
      children: [
        // ── My-location (always visible, above Navigate FAB) ──
        Positioned(
          right:  12,
          bottom: baseBottom + 58, // 58 = Navigate FAB height (48) + gap (10)
          child: SafeArea(
            top: false,
            child: FloatingActionButton.small(
              heroTag:         'locate',
              onPressed:       _centerOnUser,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1A73E8),
              elevation:       4,
              child:           const Icon(Icons.my_location),
            ),
          ),
        ),

        // ── NAVIGATE button — ALWAYS ON SCREEN ───────────────
        Positioned(
          right:  12,
          bottom: baseBottom,
          child: SafeArea(
            top: false,
            child: FloatingActionButton.extended(
              heroTag:         'navigate',
              // Always tappable — shows snack if no destination
              onPressed:       isLoading ? null : _onNavigatePressed,
              backgroundColor: hasDestination
                  ? const Color(0xFF1A73E8)
                  : Colors.grey.shade400,
              foregroundColor: Colors.white,
              elevation:       hasDestination ? 6 : 2,
              icon: isLoading
                  ? const SizedBox(
                width:  20,
                height: 20,
                child:  CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.directions, size: 22),
              label: Text(
                isLoading ? 'Finding…' : 'Navigate',
                style: const TextStyle(
                  fontWeight:    FontWeight.w700,
                  fontSize:      15,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),

        // ── Clear-route button — only when routes are showing ─
        if (_routes.isNotEmpty)
          Positioned(
            right:  12,
            bottom: baseBottom + 116, // above my-location button
            child: SafeArea(
              top: false,
              child: FloatingActionButton.small(
                heroTag:         'clear',
                onPressed: () => setState(() {
                  _routes       = [];
                  _errorMessage = null;
                }),
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade400,
                elevation:       4,
                child:           const Icon(Icons.close),
              ),
            ),
          ),
      ],
    );
  }

  /// Navigate button tap handler — always safe to call
  void _onNavigatePressed() {
    if (_destination == null) {
      // No destination set — inform the user
      _showSnack('Please select a destination first');
      return;
    }
    if (_loadingRoutes) return; // guard against double-tap
    _fetchRoutes();
  }

  // ── ROUTE CARDS (BOTTOM) ──────────────────────────────────
  Widget _buildRouteCards() {
    return Positioned(
      left:   0,
      right:  0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          color: Colors.transparent,
          height: 210,
          child: ListView.builder(
            scrollDirection:  Axis.horizontal,
            padding:          const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemCount:        _routes.length,
            itemBuilder:      (_, i) => _buildRouteCard(_routes[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteCard(RouteModel route) {
    final color = _routeColors[route.index % _routeColors.length];
    return GestureDetector(
      onTap: () => _selectRoute(route.index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width:  190,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: route.isSelected ? color : Colors.grey.shade200,
            width: route.isSelected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color:      route.isSelected
                  ? color.withOpacity(0.22)
                  : Colors.black.withOpacity(0.08),
              blurRadius:   8,
              offset:       const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:        route.isSelected
                    ? color
                    : color.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Icon(Icons.route,
                      size:  15,
                      color: route.isSelected ? Colors.white : color),
                  const SizedBox(width: 6),
                  Text(
                    'Route ${route.index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize:   13,
                      color:      route.isSelected ? Colors.white : color,
                    ),
                  ),
                  if (route.index == 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: route.isSelected
                            ? Colors.white.withOpacity(0.25)
                            : color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'FASTEST',
                        style: TextStyle(
                          fontSize:    8,
                          fontWeight:  FontWeight.w800,
                          color:       route.isSelected
                              ? Colors.white
                              : color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Distance + Time ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  _pill(Icons.straighten,   route.distanceLabel, color),
                  const SizedBox(width: 6),
                  _pill(Icons.access_time,  route.durationLabel, color),
                ],
              ),
            ),

            // ── POI stats ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Wrap(
                spacing:    5,
                runSpacing: 4,
                children: [
                  _poiChip(Icons.local_hospital,    route.stats.hospitals, const Color(0xFFEA4335)),
                  _poiChip(Icons.local_police,       route.stats.police,   const Color(0xFF1A73E8)),
                  _poiChip(Icons.local_gas_station,  route.stats.fuel,     const Color(0xFFFA7B17)),
                  _poiChip(Icons.local_cafe,         route.stats.cafes,    const Color(0xFFBF5700)),
                  _poiChip(Icons.park,               route.stats.parks,    const Color(0xFF0F9D58)),
                  _poiChip(Icons.account_balance,    route.stats.banks,    const Color(0xFF34A853)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color:        c.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: c),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: c)),
      ],
    ),
  );

  Widget _poiChip(IconData icon, int count, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color:        c.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: c),
        const SizedBox(width: 2),
        Text('$count',
            style: TextStyle(
                fontSize:   10,
                fontWeight: FontWeight.w700,
                color:      c.withOpacity(0.9))),
      ],
    ),
  );

  // ── LOADING OVERLAY ───────────────────────────────────────
  Widget _buildLoadingOverlay() {
    // Sits above route cards (210) + some padding, never covers the FABs
    return const Positioned(
      bottom: 230,
      left:   0,
      right:  0,
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width:  18,
                  height: 18,
                  child:  CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Finding best routes…',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── ERROR BANNER ──────────────────────────────────────────
  Widget _buildErrorBanner() {
    return Positioned(
      // Sits between route area and map; doesn't overlap FAB cluster
      bottom: 90,
      left:   12,
      right:  80, // leave room for FABs on the right
      child: Material(
        color:        const Color(0xFFEA4335),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines:  2,
                  overflow:  TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _errorMessage = null),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// POI BOTTOM SHEET
// ─────────────────────────────────────────────────────────────
class _PoiSheet extends StatelessWidget {
  final PlaceModel    poi;
  final VoidCallback  onNavigate;

  const _PoiSheet({required this.poi, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final meta = _categoryMeta[poi.category];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width:  40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color:        Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          Row(
            children: [
              if (meta != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: meta.color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 24),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(poi.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    if (poi.address != null)
                      Text(poi.address!,
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12)),
                    if (meta != null)
                      Text(meta.label,
                          style: TextStyle(
                              color:      meta.color,
                              fontSize:   12,
                              fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Navigate button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNavigate,
              icon:      const Icon(Icons.directions),
              label:     const Text('Navigate Here'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                padding:         const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ANIMATED GPS PULSE MARKER
// ─────────────────────────────────────────────────────────────
class _LocationPulse extends StatefulWidget {
  @override
  State<_LocationPulse> createState() => _LocationPulseState();
}

class _LocationPulseState extends State<_LocationPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync:    this,
        duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder:   (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width:  28 * _anim.value,
            height: 28 * _anim.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A73E8)
                  .withOpacity(0.22 * _anim.value),
            ),
          ),
          Container(
            width:  14,
            height: 14,
            decoration: BoxDecoration(
              shape:  BoxShape.circle,
              color:  const Color(0xFF1A73E8),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color:      const Color(0xFF1A73E8).withOpacity(0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
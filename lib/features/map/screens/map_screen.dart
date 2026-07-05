import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/providers/employees_provider.dart';
import '../../employees/widgets/employee_go_live_card.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../models/food_truck.dart';
import '../providers/map_provider.dart';
import '../widgets/map_controls.dart';
import '../widgets/map_pin_widgets.dart';
import '../widgets/map_search_widgets.dart';
import '../widgets/truck_bottom_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  StreamSubscription<MapEvent>? _mapEventSub;
  Timer? _mapMoveDebounce;
  Timer? _badgeTimer;
  bool _isFollowing = true;
  String _searchQuery = '';
  String _instantQuery = '';
  Timer? _debounce;
  List<String> _recentSearches = [];
  bool _searchFocused = false;

  // Memoized marker clustering — recomputed only when the truck list or the
  // rounded visible bounds actually change, not on every map-move frame
  // (map_screen.dart's mapEventStream emits on every intermediate frame of a
  // pan/zoom gesture). Re-running the O(n log n) sort + offset math on every
  // frame was also the root cause of a live-observed stacked-pin bug —
  // clustering was being re-run so often it didn't reliably converge to a
  // stable layout even at low truck counts.
  List<FoodTruck>? _lastClusterTrucks;
  String? _lastClusterBoundsKey;
  List<(FoodTruck, LatLng)> _cachedClusterResult = const [];

  static const _defaultCenter = LatLng(34.375, -80.074);

  @override
  void initState() {
    super.initState();
    // The map tab may start offstage (IndexedStack index > 0 on owner shell),
    // meaning flutter_map has zero paint bounds and fetches no tiles. We also
    // can't rely solely on the GPS stream because it may emit before the
    // MapController is attached. Use getLastKnownPosition (OS cache, ~10 ms)
    // to fast-path to the right location, then let the live stream take over.
    _resolveInitialCenter();
    _loadRecentSearches();
    _searchFocusNode.addListener(_onFocusChanged);
    _badgeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _resolveInitialCenter() async {
    Position? cached;
    try {
      cached = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    if (!mounted) return;
    // After the first frame the MapController is guaranteed to be attached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Attach the listener BEFORE the initial re-centering move below — if
      // MapController.move() emits its event synchronously (it does), a
      // listener attached afterward misses that very first event entirely.
      // With _clusteredMarkers' bounds-keyed memoization (MED-12), missing it
      // meant the marker layer stayed cached against the stale initial-camera
      // bounds (MapOptions.initialCenter, e.g. Hartsville) even though the
      // map had already visually moved to the user's real location (e.g.
      // Cupertino) — every truck there reads as "outside the cached bounds"
      // and renders as zero pins, correcting itself only when some unrelated
      // setState() (in practice, _badgeTimer's 1-minute tick) forced a
      // rebuild. This was a live, user-reported bug: trucks missing for up
      // to a full minute after returning to the map from a screen outside
      // the shell (e.g. the guest login redirect).
      _mapEventSub = _mapController.mapEventStream.listen((_) {
        // Debounced, same pattern as search (_onSearchChanged) — mapEventStream
        // emits on every intermediate frame of a pan/zoom gesture, not just at
        // gesture-end, so an un-debounced setState here reruns this screen's
        // full build() (including marker clustering) up to 60x/sec during a drag.
        _mapMoveDebounce?.cancel();
        _mapMoveDebounce = Timer(const Duration(milliseconds: 120), () {
          if (mounted) setState(() {});
        });
      });
      if (_isFollowing) {
        final pos = cached ?? ref.read(userLocationProvider).asData?.value;
        if (pos != null) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 14.0);
          // Belt-and-suspenders on top of the listener reordering above:
          // force one immediate rebuild with the new camera position rather
          // than depend entirely on mapEventStream firing/being caught for
          // this specific, critical one-time centering move.
          if (mounted) setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
    _mapMoveDebounce?.cancel();
    _badgeTimer?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchFocusNode.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() => _searchFocused = _searchFocusNode.hasFocus);
  }

  List<FoodTruck> _sortByDistance(List<FoodTruck> trucks, Position? pos) {
    if (pos == null) return trucks;
    return trucks.toList()
      ..sort((a, b) {
        final da = (a.latitude != null && a.longitude != null)
            ? Geolocator.distanceBetween(pos.latitude, pos.longitude, a.latitude!, a.longitude!)
            : double.maxFinite;
        final db = (b.latitude != null && b.longitude != null)
            ? Geolocator.distanceBetween(pos.latitude, pos.longitude, b.latitude!, b.longitude!)
            : double.maxFinite;
        return da.compareTo(db);
      });
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _recentSearches = prefs.getStringList('recent_searches') ?? []);
    }
  }

  Future<void> _saveSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final updated = [q, ..._recentSearches.where((s) => s != q)].take(5).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  Future<void> _removeRecent(String query) async {
    final updated = _recentSearches.where((s) => s != query).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', updated);
    setState(() => _recentSearches = updated);
  }

  void _applyRecent(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(offset: query.length);
    _debounce?.cancel();
    setState(() => _searchQuery = query);
  }

  void _onSearchChanged(String value) {
    final trimmed = value.trim();
    setState(() => _instantQuery = trimmed);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _searchQuery = trimmed);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = '';
      _instantQuery = '';
    });
  }

  void _onSearchResultTapped(FoodTruck truck) {
    _saveSearch(_instantQuery.isNotEmpty ? _instantQuery : _searchQuery);
    _clearSearch();
    setState(() => _isFollowing = false);
    _mapController.move(LatLng(truck.latitude!, truck.longitude!), 16.0);
    _onTruckTapped(truck);
  }

  void _onTruckTapped(FoodTruck truck) {
    _searchFocusNode.unfocus();
    ref.read(selectedTruckProvider.notifier).select(truck);
    setState(() => _isFollowing = false);
    _mapController.move(
      LatLng(truck.latitude!, truck.longitude!),
      _mapController.camera.zoom,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TruckBottomSheet(truck: truck),
    ).whenComplete(() {
      if (mounted) ref.read(selectedTruckProvider.notifier).select(null);
    });
  }

  void _recenter() {
    final pos = ref.read(userLocationProvider).asData?.value;
    if (pos != null) {
      setState(() => _isFollowing = true);
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  // Spreads markers that share the same location into a small circle so they
  // don't completely overlap. Trucks within ~5 m of each other are grouped.
  List<(FoodTruck, LatLng)> _applyClusterOffsets(List<FoodTruck> trucks) {
    const double threshold = 0.00005; // ~5 m — treated as same location
    const double spread    = 0.00022; // ~24 m radius — enough to see both pins

    final groups    = <int, List<int>>{}; // representative index → members
    final assigned  = <int, int>{};      // truck index → representative

    for (int i = 0; i < trucks.length; i++) {
      final t = trucks[i];
      if (t.latitude == null || t.longitude == null) continue;
      bool found = false;
      for (final rep in groups.keys) {
        final r = trucks[rep];
        if ((t.latitude! - r.latitude!).abs() < threshold &&
            (t.longitude! - r.longitude!).abs() < threshold) {
          groups[rep]!.add(i);
          assigned[i] = rep;
          found = true;
          break;
        }
      }
      if (!found) {
        groups[i] = [i];
        assigned[i] = i;
      }
    }

    final result = <(FoodTruck, LatLng)>[];
    for (int i = 0; i < trucks.length; i++) {
      final truck = trucks[i];
      if (truck.latitude == null || truck.longitude == null) continue;
      final rep   = assigned[i]!;
      final group = groups[rep]!;
      if (group.length == 1) {
        result.add((truck, LatLng(truck.latitude!, truck.longitude!)));
      } else {
        final idx   = group.indexOf(i);
        final n     = group.length;
        final angle = (2 * math.pi * idx) / n - math.pi / 2;
        result.add((truck, LatLng(
          truck.latitude!  + spread * math.cos(angle),
          truck.longitude! + spread * math.sin(angle),
        )));
      }
    }
    return result;
  }

  // Returns true when a truck's coordinate falls within the current visible bounds.
  // Falls back to true if the camera isn't ready yet so no markers are hidden early.
  bool _inVisibleBounds(FoodTruck truck) {
    try {
      return _mapController.camera.visibleBounds
          .contains(LatLng(truck.latitude!, truck.longitude!));
    } catch (_) {
      return true;
    }
  }

  // Rounds the visible bounds to ~110 m so the memoization key below is
  // stable across sub-pixel jitter/tiny pans, only changing when the
  // viewport moves meaningfully.
  String _roundedBoundsKey() {
    try {
      final b = _mapController.camera.visibleBounds;
      String r(double v) => v.toStringAsFixed(3);
      return '${r(b.south)},${r(b.west)},${r(b.north)},${r(b.east)}';
    } catch (_) {
      return 'unbounded';
    }
  }

  // Filters to visible bounds, sorts, and clusters — memoized against the
  // truck list identity + rounded bounds so this only recomputes when either
  // actually changes, not on every rebuild the debounced map-move listener
  // above triggers.
  List<(FoodTruck, LatLng)> _clusteredMarkers(List<FoodTruck> trucks) {
    final boundsKey = _roundedBoundsKey();
    if (identical(trucks, _lastClusterTrucks) && boundsKey == _lastClusterBoundsKey) {
      return _cachedClusterResult;
    }
    final visible = trucks.where(_inVisibleBounds).toList()
      ..sort((a, b) {
        if (a.sessionStartedAt == null) return -1;
        if (b.sessionStartedAt == null) return 1;
        return b.sessionStartedAt!.compareTo(a.sessionStartedAt!);
      });
    final result = _applyClusterOffsets(visible);
    _lastClusterTrucks = trucks;
    _lastClusterBoundsKey = boundsKey;
    _cachedClusterResult = result;
    return result;
  }

  // Returns (edge position, scale) for an off-screen truck, or null if on-screen.
  // Scale shrinks from 1.0 → 0.5 the farther the truck is beyond the visible area.
  (Offset, double)? _edgePosition(LatLng truckPos, Size stackSize) {
    try {
      final pt = _mapController.camera.latLngToScreenOffset(truckPos);
      final tx = pt.dx;
      final ty = pt.dy;
      if (tx >= 0 && tx <= stackSize.width && ty >= 0 && ty <= stackSize.height) {
        return null;
      }
      const half = 20.0;
      final minX = half;
      final maxX = stackSize.width - half;
      final minY = half;
      final maxY = stackSize.height - half;
      final cx = stackSize.width / 2;
      final cy = stackSize.height / 2;
      final dx = tx - cx;
      final dy = ty - cy;
      if (dx == 0 && dy == 0) return null;
      var t = double.infinity;
      if (dx > 0) t = math.min(t, (maxX - cx) / dx);
      if (dx < 0) t = math.min(t, (minX - cx) / dx);
      if (dy > 0) t = math.min(t, (maxY - cy) / dy);
      if (dy < 0) t = math.min(t, (minY - cy) / dy);
      if (!t.isFinite || t <= 0) return null;

      final offX = math.max(0.0, math.max(-tx, tx - stackSize.width));
      final offY = math.max(0.0, math.max(-ty, ty - stackSize.height));
      final offDist = math.sqrt(offX * offX + offY * offY);
      final scale = 1.0 - 0.5 * (offDist / 400.0).clamp(0.0, 1.0);

      return (
        Offset(
          (cx + dx * t).clamp(minX, maxX),
          (cy + dy * t).clamp(minY, maxY),
        ),
        scale,
      );
    } catch (_) {
      return null;
    }
  }

  List<Widget> _buildEdgeIndicators(Size stackSize, List<FoodTruck> trucks, Set<String> favIds) {
    return trucks
        .where((t) => t.isOpen && favIds.contains(t.id))
        .expand((truck) {
          final result = _edgePosition(LatLng(truck.latitude!, truck.longitude!), stackSize);
          if (result == null) return <Widget>[];
          final (pos, scale) = result;
          return <Widget>[
            Positioned(
              left: pos.dx - 20,
              top: pos.dy - 20,
              child: Transform.scale(
                scale: scale,
                child: OffScreenIndicator(
                  truck: truck,
                  onTap: () => _onTruckTapped(truck),
                ),
              ),
            ),
          ];
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final trucksAsync = ref.watch(activeTrucksProvider);
    final locationAsync = ref.watch(userLocationProvider);
    // Pre-load so the heart state is ready before any bottom sheet opens.
    final favIds = ref.watch(favoritedTruckIdsProvider).asData?.value ?? {};
    final searchAsync = ref.watch(truckSearchProvider(_searchQuery));
    final employeeTrucks = ref.watch(myEmployeeTrucksProvider).asData?.value ?? [];

    // Client-side suggestions from already-loaded trucks — shown instantly
    // while the debounce is still in flight (_instantQuery != _searchQuery).
    final activeTrucks = trucksAsync.asData?.value ?? [];
    final userPos = locationAsync.asData?.value;
    final q = _instantQuery.toLowerCase();
    final filtered = _instantQuery.isEmpty
        ? <FoodTruck>[]
        : activeTrucks
            .where((t) =>
                t.name.toLowerCase().contains(q) ||
                t.cuisineType.toLowerCase().contains(q))
            .toList();
    final localSuggestions = _sortByDistance(filtered, userPos).take(5).toList();

    // Use server results once the debounce has caught up; local data before.
    // Both paths sorted by distance so the nearest match surfaces first.
    final dropdownValue = (_searchQuery == _instantQuery && _instantQuery.isNotEmpty)
        ? searchAsync.whenData((trucks) => _sortByDistance(trucks, userPos))
        : AsyncData<List<FoodTruck>>(localSuggestions);
    final topPad = MediaQuery.of(context).padding.top;

    // Follow user position whenever _isFollowing is true.
    ref.listen<AsyncValue<Position?>>(userLocationProvider, (_, next) {
      if (_isFollowing) {
        final pos = next.asData?.value;
        if (pos != null) {
          _mapController.move(
            LatLng(pos.latitude, pos.longitude),
            _mapController.camera.zoom,
          );
        }
      }
    });

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final stackSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 14.0,
              onTap: (_, _) {
                ref.read(selectedTruckProvider.notifier).select(null);
                _searchFocusNode.unfocus();
              },
              // User drag → stop following.
              onPositionChanged: (_, hasGesture) {
                if (hasGesture) {
                  _searchFocusNode.unfocus();
                  if (_isFollowing) setState(() => _isFollowing = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: Theme.of(context).brightness == Brightness.dark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.farlo.app',
              ),
              if (userPos != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(userPos.latitude, userPos.longitude),
                      radius: 8,
                      color: Colors.blue.withValues(alpha: 0.25),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                      useRadiusInMeter: false,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: () {
                  return _clusteredMarkers(activeTrucks).map(
                    ((FoodTruck, LatLng) pair) {
                      final (truck, point) = pair;
                      final diff = truck.sessionStartedAt != null
                          ? DateTime.now().difference(truck.sessionStartedAt!)
                          : null;
                      final showBadge = diff != null && diff.inMinutes >= 10;
                      return Marker(
                        point: point,
                        width: showBadge ? 72 : 44,
                        height: showBadge ? 76 : 44,
                        alignment: showBadge
                            ? const Alignment(0, -0.33)
                            : Alignment.center,
                        child: Semantics(
                          label: '${truck.name}, ${truck.isOpen ? "open" : "closed"}',
                          button: true,
                          child: GestureDetector(
                            onTap: () => _onTruckTapped(truck),
                            child: TruckPin(
                              isOpen: truck.isOpen,
                              logoUrl: truck.logoUrl,
                              sessionStartedAt: truck.sessionStartedAt,
                            ),
                          ),
                        ),
                      );
                    },
                  ).toList();
                }(),
              ),
            ],
          ),
          // Floating search bar + results
          Positioned(
            top: topPad + 12,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MapSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
                if (_instantQuery.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SearchResults(
                    searchAsync: dropdownValue,
                    onTap: _onSearchResultTapped,
                    userPos: userPos,
                  ),
                ] else if (_searchFocused && _recentSearches.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  RecentSearches(
                    recents: _recentSearches,
                    onTap: _applyRecent,
                    onRemove: _removeRecent,
                  ),
                ],
              ],
            ),
          ),
          // Recenter button — only visible when user has panned away.
          if (!_isFollowing)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(child: RecenterButton(onTap: _recenter)),
            ),
          if (trucksAsync.isLoading && _searchQuery.isEmpty)
            Positioned(
              top: topPad + 72,
              left: 0,
              right: 0,
              child: const Center(child: MapChip(label: 'Loading businesses…')),
            ),
          if ((trucksAsync.asData?.value.isEmpty ?? false) && _searchQuery.isEmpty)
            Positioned(
              top: topPad + 72,
              left: 0,
              right: 0,
              child: const Center(child: MapChip(label: 'No active businesses in this area')),
            ),
          // Employee go-live cards — pinned at bottom for assigned trucks
          if (employeeTrucks.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: employeeTrucks
                    .map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: EmployeeGoLiveCard(truckId: t.id, truckName: t.name),
                        ))
                    .toList(),
              ),
            ),
          ..._buildEdgeIndicators(stackSize, activeTrucks, favIds),
        ],
      );
        },
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../employees/providers/employees_provider.dart';
import '../../employees/widgets/employee_go_live_card.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../models/food_truck.dart';
import '../providers/map_provider.dart';
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
  Timer? _badgeTimer;
  bool _isFollowing = true;
  String _searchQuery = '';
  String _instantQuery = '';
  Timer? _debounce;
  List<String> _recentSearches = [];
  bool _searchFocused = false;

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
      if (_isFollowing) {
        final pos = cached ?? ref.read(userLocationProvider).asData?.value;
        if (pos != null) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 14.0);
        }
      }
      _mapEventSub = _mapController.mapEventStream.listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
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
                child: _OffScreenIndicator(
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
                  final sorted = trucksAsync.asData?.value
                          .where(_inVisibleBounds)
                          .toList() ?? [];
                  sorted.sort((a, b) {
                    if (a.sessionStartedAt == null) return -1;
                    if (b.sessionStartedAt == null) return 1;
                    return b.sessionStartedAt!.compareTo(a.sessionStartedAt!);
                  });
                  return _applyClusterOffsets(sorted).map(
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
                        child: GestureDetector(
                          onTap: () => _onTruckTapped(truck),
                          child: _TruckPin(
                            isOpen: truck.isOpen,
                            logoUrl: truck.logoUrl,
                            sessionStartedAt: truck.sessionStartedAt,
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
                _SearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
                if (_instantQuery.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _SearchResults(
                    searchAsync: dropdownValue,
                    onTap: _onSearchResultTapped,
                    userPos: userPos,
                  ),
                ] else if (_searchFocused && _recentSearches.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _RecentSearches(
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
              child: Center(child: _RecenterButton(onTap: _recenter)),
            ),
          if (trucksAsync.isLoading && _searchQuery.isEmpty)
            Positioned(
              top: topPad + 72,
              left: 0,
              right: 0,
              child: const Center(child: _MapChip(label: 'Loading trucks…')),
            ),
          if ((trucksAsync.asData?.value.isEmpty ?? false) && _searchQuery.isEmpty)
            Positioned(
              top: topPad + 72,
              left: 0,
              right: 0,
              child: const Center(child: _MapChip(label: 'No active businesses in this area')),
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

class _OffScreenIndicator extends StatelessWidget {
  const _OffScreenIndicator({required this.truck, required this.onTap});
  final FoodTruck truck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: primary, width: 2.5),
          color: primary,
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.45),
              blurRadius: 10,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: truck.logoUrl != null
              ? Image.network(
                  truck.logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.storefront_outlined, color: Colors.white, size: 22),
                )
              : const Icon(Icons.storefront_outlined, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _TruckPin extends StatelessWidget {
  const _TruckPin({required this.isOpen, this.logoUrl, this.sessionStartedAt});

  final bool isOpen;
  final String? logoUrl;
  final DateTime? sessionStartedAt;

  String? get _badge {
    if (sessionStartedAt == null) return null;
    final diff = DateTime.now().difference(sessionStartedAt!);
    if (diff.inMinutes < 10) return null;
    if (diff.inDays >= 1) return 'Opened ${diff.inDays}d';
    if (diff.inHours >= 1) return 'Opened ${diff.inHours}h';
    return 'Opened ${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isOpen ? Theme.of(context).colorScheme.primary : AppColors.textHint;
    final badge = _badge;
    final circle = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 2.5),
        color: accentColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: logoUrl != null
            ? Image.network(
                logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _PinFallback(accentColor: accentColor),
              )
            : _PinFallback(accentColor: accentColor),
      ),
    );

    if (badge == null) return circle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _PinFallback extends StatelessWidget {
  const _PinFallback({required this.accentColor});
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: accentColor,
      child: const Center(child: Icon(Icons.storefront_outlined, color: Colors.white, size: 24)),
    );
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.my_location, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Recenter',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search, color: AppColors.textHint, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Search by name or cuisine…',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (controller.text.isNotEmpty) ...[
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close, color: AppColors.textHint, size: 18),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.searchAsync, required this.onTap, this.userPos});

  final AsyncValue<List<FoodTruck>> searchAsync;
  final ValueChanged<FoodTruck> onTap;
  final Position? userPos;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: searchAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (_, _) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Search failed', style: TextStyle(color: AppColors.textHint)),
          ),
          data: (trucks) {
            if (trucks.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No businesses found', style: TextStyle(color: AppColors.textHint, fontSize: 14)),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: trucks.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final truck = trucks[i];
                return InkWell(
                  onTap: () => onTap(truck),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: truck.isOpen
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                                : AppColors.divider,
                          ),
                          child: ClipOval(
                            child: truck.logoUrl != null
                                ? Image.network(truck.logoUrl!, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.storefront_outlined, size: 20, color: AppColors.textHint))
                                : const Icon(Icons.storefront_outlined, size: 20, color: AppColors.textHint),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(truck.name, style: AppTextStyles.label),
                              Row(
                                children: [
                                  Text(truck.cuisineType, style: AppTextStyles.caption),
                                  if (userPos != null) ...[
                                    const SizedBox(width: 6),
                                    _DistanceChip(
                                      meters: Geolocator.distanceBetween(
                                        userPos!.latitude, userPos!.longitude,
                                        truck.latitude!, truck.longitude!,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (truck.isOpen ? AppColors.openGreen : AppColors.textHint).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            truck.isOpen ? 'Open' : 'Closed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: truck.isOpen ? AppColors.openGreen : AppColors.textHint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DistanceChip extends StatelessWidget {
  const _DistanceChip({required this.meters});

  final double meters;

  @override
  Widget build(BuildContext context) {
    final miles = meters / 1609.344;
    final label = miles < 0.1 ? 'Nearby' : '${miles.toStringAsFixed(1)} mi';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), width: 0.5),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), offset: Offset(0, 1), blurRadius: 1, spreadRadius: -1),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me, size: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.recents,
    required this.onTap,
    required this.onRemove,
  });

  final List<String> recents;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  const Text(
                    'Recent searches',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            ...recents.map(
              (q) => InkWell(
                onTap: () => onTap(q),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 16, color: AppColors.textHint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(q, style: const TextStyle(fontSize: 14)),
                      ),
                      GestureDetector(
                        onTap: () => onRemove(q),
                        behavior: HitTestBehavior.opaque,
                        child: const Icon(Icons.close, size: 16, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
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
  bool _isFollowing = true;

  static const _defaultCenter = LatLng(37.7749, -122.4194);

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onTruckTapped(FoodTruck truck) {
    ref.read(selectedTruckProvider.notifier).select(truck);
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

  @override
  Widget build(BuildContext context) {
    final trucksAsync = ref.watch(activeTrucksProvider);
    final locationAsync = ref.watch(userLocationProvider);
    final userPos = locationAsync.asData?.value;

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
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 14.0,
              onTap: (_, _) => ref.read(selectedTruckProvider.notifier).select(null),
              // User drag → stop following.
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _isFollowing) {
                  setState(() => _isFollowing = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.goodtruckfinder.app',
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
                markers: trucksAsync.asData?.value
                        .map(
                          (truck) => Marker(
                            point: LatLng(truck.latitude, truck.longitude),
                            width: 44,
                            height: 44,
                            child: GestureDetector(
                              onTap: () => _onTruckTapped(truck),
                              child: _TruckPin(isOpen: truck.isOpen),
                            ),
                          ),
                        )
                        .toList() ??
                    [],
              ),
            ],
          ),
          // Recenter button — only visible when user has panned away.
          if (!_isFollowing)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(child: _RecenterButton(onTap: _recenter)),
            ),
          if (trucksAsync.isLoading)
            const Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Center(child: _MapChip(label: 'Loading trucks…')),
            ),
          if (trucksAsync.asData?.value.isEmpty ?? false)
            const Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Center(child: _MapChip(label: 'No active trucks in this area')),
            ),
        ],
      ),
    );
  }
}

class _TruckPin extends StatelessWidget {
  const _TruckPin({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isOpen ? AppColors.primary : AppColors.textHint,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.lunch_dining, color: Colors.white, size: 24),
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.my_location, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'Recenter',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
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
        color: Colors.white,
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

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // Default center: San Francisco. Replaced by GPS on permission grant.
  static const _defaultCenter = LatLng(37.7749, -122.4194);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userLocationProvider.future).then((position) {
        if (position != null && mounted) {
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            14.0,
          );
        }
      });
    });
  }

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

  void _centerOnUser() {
    final pos = ref.read(userLocationProvider).asData?.value;
    if (pos != null) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trucksAsync = ref.watch(activeTrucksProvider);
    final locationAsync = ref.watch(userLocationProvider);
    final userPos = locationAsync.asData?.value;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 12.0,
              onTap: (_, _) => ref.read(selectedTruckProvider.notifier).select(null),
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
                      color: AppColors.primary.withValues(alpha: 0.25),
                      borderColor: AppColors.primary,
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
          // Location button
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingActionButton.small(
              heroTag: 'location_fab',
              onPressed: _centerOnUser,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 2,
              child: const Icon(Icons.my_location),
            ),
          ),
          // Loading indicator while fetching trucks
          if (trucksAsync.isLoading)
            const Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Center(
                child: _MapChip(label: 'Loading trucks…'),
              ),
            ),
          if (trucksAsync.asData?.value.isEmpty ?? false)
            const Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Center(
                child: _MapChip(label: 'No active trucks in this area'),
              ),
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

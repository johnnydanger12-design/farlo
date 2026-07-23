import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';

// Fixed-center-pin picker: the pin stays locked to the screen center and the
// map pans underneath it, rather than a draggable marker — flutter_map (this
// app's map library) has no built-in draggable-marker support, and this is
// the standard pattern for "drop a pin" pickers generally. Returns the final
// center via Navigator.pop when confirmed; the caller decides where that
// correction actually gets written (a planned_locations row for a mobile
// truck's currently-active announced location, or straight onto the truck's
// own record for a fixed location) since that's a business decision this
// screen has no context for.
class AdjustLocationPinScreen extends StatefulWidget {
  const AdjustLocationPinScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.subtitle,
  });

  final double initialLat;
  final double initialLng;
  final String subtitle;

  @override
  State<AdjustLocationPinScreen> createState() => _AdjustLocationPinScreenState();
}

class _AdjustLocationPinScreenState extends State<AdjustLocationPinScreen> {
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust Pin Location'),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.initialLat, widget.initialLng),
              initialZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: Theme.of(context).brightness == Brightness.dark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.farlo.app',
              ),
            ],
          ),
          // Fixed center pin — the map moves underneath it, it never moves
          // itself, so the anchor point is always exactly the screen center.
          IgnorePointer(
            child: Padding(
              // Nudge up by roughly half the pin's own height so the actual
              // point (its bottom tip) lands on center, not the icon's middle.
              padding: const EdgeInsets.only(bottom: 32),
              child: Icon(Icons.location_on, size: 44, color: AppColors.primary),
            ),
          ),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Pan the map so the pin sits exactly where you park — ${widget.subtitle}',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            bottom: AppSpacing.lg,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _mapController.camera.center),
              child: const Text('Save Pin Location'),
            ),
          ),
        ],
      ),
    );
  }
}

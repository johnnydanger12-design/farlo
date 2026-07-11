import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_text_styles.dart';
import 'snackbar_extensions.dart';

// Pure decision logic, extracted from the async orchestration below so it's
// unit-testable without a device/plugin channel. This is exactly where the
// real bug lived: which permission source is trusted for "does the user
// already have what we need." permission_handler's own
// Permission.locationAlways.status/request() result has a documented
// upstream bug where it gets stuck reporting denied/permanentlyDenied on
// iOS even after the user has genuinely granted "Always" in Settings
// (confirmed live on a real device: full phone restart didn't clear it,
// ruling out mere cache staleness). geolocator_apple reads CoreLocation's
// authorization status directly and correctly reports LocationPermission
// .always, so these helpers -- and every gate below -- consult ONLY
// Geolocator's LocationPermission, never permission_handler's status/result.
// permission_handler is still used for exactly one thing it's needed for:
// firing the native "upgrade to Always" prompt on iOS, since Geolocator has
// no API to trigger that (see LocationTrackingService's class doc).
// See Baseflow/flutter-permission-handler#721, #1391, #780.

/// Whether this permission level is sufficient to go live (background
/// tracking requires "Always", not just "While In Use").
@visibleForTesting
bool hasRequiredLocationAccess(LocationPermission permission) =>
    permission == LocationPermission.always;

/// Whether foreground location was denied outright (as opposed to just not
/// yet elevated to "Always").
@visibleForTesting
bool isForegroundLocationDenied(LocationPermission permission) =>
    permission == LocationPermission.denied ||
    permission == LocationPermission.deniedForever;

/// Shows a prominent background-location disclosure (required by Google Play
/// policy on Android; matches Apple's own App Review expectation of an
/// in-app explanation before requesting "Always" on iOS) and then requests
/// the necessary permissions on both platforms.
///
/// Returns true if the caller should proceed with going live, false if the
/// user declined or permission was denied.
Future<bool> requestLocationForGoLive(BuildContext context) async {
  LocationPermission permission = await Geolocator.checkPermission();

  // If background permission is already granted, nothing to explain.
  if (!hasRequiredLocationAccess(permission)) {
    if (!context.mounted) return false;
    final accepted = await _showDisclosureSheet(context);
    if (!accepted) return false;
  }

  // Step 1 — foreground location (both platforms). Required before iOS will
  // even consider an "Always" request — permission_handler_apple's own
  // native code errors with MISSING_WHENINUSE_PERMISSION otherwise.
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (isForegroundLocationDenied(permission)) {
    if (context.mounted) {
      context.showError('Location permission is required to go live.');
    }
    return false;
  }

  // Step 2 — background location (both platforms).
  // On Android 11+ this opens Settings; the system dialog explains
  // "Allow all the time". On iOS, since "When In Use" is already granted,
  // this triggers CoreLocation's native "Always" upgrade prompt directly
  // (no Settings round-trip needed the first time). We show our disclosure
  // first so users understand why, on both platforms.
  if (!hasRequiredLocationAccess(permission)) {
    await Permission.locationAlways.request();
    // Re-check via Geolocator, not permission_handler's own request()
    // result -- that result is the same unreliable value as .status above.
    final recheck = await Geolocator.checkPermission();
    if (!hasRequiredLocationAccess(recheck)) {
      if (context.mounted) {
        context.showError(
          'Background location is required to stay visible on the map when the app is minimised.',
          action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
        );
      }
      return false;
    }
  }

  return true;
}

Future<bool> _showDisclosureSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _LocationDisclosureSheet(),
  );
  return result ?? false;
}

class _LocationDisclosureSheet extends StatelessWidget {
  const _LocationDisclosureSheet();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Icon
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 26),
          ),

          Text('Location used in background', style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.sm),

          Text(
            'To show your business on the Farlo map while you\'re serving customers, '
            'Farlo collects your location even when the app is closed or not in use.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),

          Text(
            'This data is only visible to customers on the map while your business '
            'is marked as open. Location sharing stops the moment you close.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),

          Text(
            Platform.isIOS
                ? 'On the next screen, select "Change to Always Allow" to enable this feature.'
                : 'On the next screen, select "Allow all the time" to enable this feature.',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),

          // Privacy policy link
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://farlo.app/privacy'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Privacy Policy',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not Now'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

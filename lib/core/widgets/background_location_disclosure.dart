import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shows a prominent background-location disclosure on Android (required by
/// Google Play policy) and then requests the necessary permissions.
///
/// Returns true if the caller should proceed with going live, false if the
/// user declined or permission was denied.
///
/// On iOS, skips the disclosure and falls through to Geolocator directly
/// (CoreLocation handles the permission UI natively).
Future<bool> requestLocationForGoLive(BuildContext context) async {
  if (Platform.isAndroid) {
    final bgStatus = await Permission.locationAlways.status;

    // If background permission is already granted, nothing to explain.
    if (!bgStatus.isGranted) {
      if (!context.mounted) return false;
      final accepted = await _showDisclosureDialog(context);
      if (!accepted) return false;
    }
  }

  // Step 1 — foreground location (both platforms).
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever ||
      permission == LocationPermission.denied) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is required to go live.')),
      );
    }
    return false;
  }

  // Step 2 — background location (Android only).
  // On Android 11+ this opens Settings; the system dialog explains
  // "Allow all the time". We show our disclosure first so users understand why.
  if (Platform.isAndroid) {
    final bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      final result = await Permission.locationAlways.request();
      if (!result.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Background location is required to stay visible on the map when the app is minimised.',
              ),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: openAppSettings,
              ),
            ),
          );
        }
        return false;
      }
    }
  }

  return true;
}

Future<bool> _showDisclosureDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Location used in background'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'To show your business on the Farlo map while you\'re serving '
              'customers, Farlo collects your location even when the app is '
              'closed or not in use.',
            ),
            SizedBox(height: 12),
            Text(
              'This location data is visible to customers on the map only '
              'while you have your business marked as open. It stops as soon '
              'as you close.',
            ),
            SizedBox(height: 12),
            Text(
              'On the next screen, select "Allow all the time" to enable '
              'this feature.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not Now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return result ?? false;
}

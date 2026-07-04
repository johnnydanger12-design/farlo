import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Location tracking for truck owners while live.
///
/// Start on go-live, stop on go-offline. Uses distance-based triggering
/// (30 m) with a 10-second write throttle so stationary trucks barely
/// touch the DB and moving trucks stay accurate without hammering Supabase.
///
/// Android: runs as a foreground service with a persistent notification, so
/// it keeps updating while the app is backgrounded (a deliberate, working
/// background-tracking path).
///
/// iOS: foreground-only, by design, not by omission. Info.plist only ever
/// declared NSLocationWhenInUseUsageDescription, which means
/// geolocator_apple's permission request only ever obtains "When In Use"
/// authorization — the app never actually had a path to "Always"
/// authorization, so allowBackgroundLocationUpdates could never take effect
/// (app-store-review.md Finding 5.1). Rather than build the second-step
/// Always-upgrade flow that would require, this scopes the declared
/// capability down to match what actually runs: no UIBackgroundModes, no
/// Always usage description, no allowBackgroundLocationUpdates. A truck's
/// live position naturally goes stale once the owner backgrounds the app,
/// same as most non-navigation apps — surfacing that honestly is safer than
/// silently promising continuous tracking that was never really happening.
class LocationTrackingService {
  LocationTrackingService._();
  static final LocationTrackingService instance = LocationTrackingService._();

  StreamSubscription<Position>? _sub;
  DateTime? _lastWrite;

  bool get isRunning => _sub != null;

  Future<void> start({
    required Future<void> Function(double lat, double lng, {String? address}) onLocation,
  }) async {
    await stop();

    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Your location is being shared with customers',
          notificationTitle: 'Farlo — Open',
          enableWakeLock: true,
        ),
      );
    } else {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        activityType: ActivityType.automotiveNavigation,
      );
    }

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        final now = DateTime.now();
        if (_lastWrite != null && now.difference(_lastWrite!).inSeconds < 10) return;
        _lastWrite = now;

        String? address;
        try {
          final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (marks.isNotEmpty) {
            final p = marks.first;
            final street = [
              if (p.subThoroughfare?.isNotEmpty ?? false) p.subThoroughfare!,
              if (p.thoroughfare?.isNotEmpty ?? false) p.thoroughfare!,
            ].join(' ');
            final city = p.locality ?? '';
            if (street.isNotEmpty && city.isNotEmpty) {
              address = '$street, $city';
            } else if (city.isNotEmpty) {
              address = city;
            } else if (street.isNotEmpty) {
              address = street;
            }
          }
        } catch (_) {}

        await onLocation(pos.latitude, pos.longitude, address: address);
      },
      onError: (_) {},
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _lastWrite = null;
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Continuous background location tracking for truck owners while live.
///
/// Start on go-live, stop on go-offline. Uses distance-based triggering
/// (30 m) with a 10-second write throttle so stationary trucks barely
/// touch the DB and moving trucks stay accurate without hammering Supabase.
///
/// Android: runs as a foreground service with a persistent notification.
/// iOS: runs in background via UIBackgroundModes + allowBackgroundLocationUpdates.
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
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
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

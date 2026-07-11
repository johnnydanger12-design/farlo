import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:farlo/core/widgets/background_location_disclosure.dart';

void main() {
  // Regression test for the "Go Live" permission loop found live in
  // production (Caroline / Burgers on Wheels, 2026-07-11): the previous
  // implementation trusted permission_handler's own
  // Permission.locationAlways.status/request() result, which has a
  // documented upstream bug (Baseflow/flutter-permission-handler#721,
  // #1391, #780) where it can get stuck reporting denied/permanentlyDenied
  // on iOS even after the user has genuinely granted "Always" in Settings —
  // confirmed live: a full phone restart didn't clear it. The fix routes
  // every gate through Geolocator's LocationPermission instead. These tests
  // pin down that decision logic so a future edit can't silently reintroduce
  // trust in the unreliable source without a test failing.
  group('hasRequiredLocationAccess', () {
    test('true only for LocationPermission.always', () {
      expect(hasRequiredLocationAccess(LocationPermission.always), isTrue);
    });

    test('false for whileInUse — this is the exact bug class: "granted but '
        'not Always" must never be treated as sufficient', () {
      expect(hasRequiredLocationAccess(LocationPermission.whileInUse), isFalse);
    });

    test('false for denied', () {
      expect(hasRequiredLocationAccess(LocationPermission.denied), isFalse);
    });

    test('false for deniedForever', () {
      expect(hasRequiredLocationAccess(LocationPermission.deniedForever), isFalse);
    });

    test('false for unableToDetermine', () {
      expect(hasRequiredLocationAccess(LocationPermission.unableToDetermine), isFalse);
    });
  });

  group('isForegroundLocationDenied', () {
    test('true for denied', () {
      expect(isForegroundLocationDenied(LocationPermission.denied), isTrue);
    });

    test('true for deniedForever', () {
      expect(isForegroundLocationDenied(LocationPermission.deniedForever), isTrue);
    });

    test('false for whileInUse — has enough to proceed to the background '
        'upgrade step, must not be treated as a hard denial', () {
      expect(isForegroundLocationDenied(LocationPermission.whileInUse), isFalse);
    });

    test('false for always', () {
      expect(isForegroundLocationDenied(LocationPermission.always), isFalse);
    });
  });
}

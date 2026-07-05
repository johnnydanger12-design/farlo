import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// security.md §3 Abuse Scenario #2 — "Google Cloud billing drain via the
// embedded client API key": GOOGLE_PLACES_API_KEY used to be compiled
// straight into the shipped binary via a dart-define, extractable via
// `strings app.apk | grep AIzaSy` with no rate limit and no way to tell the
// calls didn't come from the real app. The fix proxies autocomplete through
// the `places-autocomplete` Edge Function instead (server holds the key) and
// rotated the previously-exposed key. This test guards the structural half
// of that fix — no Dart source should ever read this key back into the
// client — so a future change can't silently reintroduce the same exposure.
void main() {
  test('no lib/ source file reads GOOGLE_PLACES_API_KEY via a dart-define', () {
    final libDir = Directory('lib');
    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      if (content.contains("fromEnvironment('GOOGLE_PLACES_API_KEY')") ||
          content.contains('fromEnvironment("GOOGLE_PLACES_API_KEY")')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'GOOGLE_PLACES_API_KEY must never be read into client code again — '
          'Places autocomplete goes through the places-autocomplete Edge Function '
          'proxy instead (places_autocomplete_field.dart). Found it read in: $offenders',
    );
  });

  test('places_autocomplete_field.dart calls the proxy, not Google directly', () {
    final file = File('lib/features/bookings/widgets/places_autocomplete_field.dart');
    expect(file.existsSync(), isTrue, reason: 'expected file moved — update this test to match');

    final content = file.readAsStringSync();
    expect(
      content.contains('places-autocomplete'),
      isTrue,
      reason: 'expected the client to call the places-autocomplete Edge Function proxy',
    );
    expect(
      content.contains('maps.googleapis.com'),
      isFalse,
      reason: 'the client must never call Google Places directly — that bypasses the proxy '
          'entirely and reintroduces the same abuse surface a rotated/removed key was meant to close',
    );
  });
}

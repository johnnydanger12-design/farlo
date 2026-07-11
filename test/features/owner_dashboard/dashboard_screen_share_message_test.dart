import 'package:flutter_test/flutter_test.dart';
import 'package:farlo/features/owner_dashboard/screens/dashboard_screen.dart';

void main() {
  // Regression test for the Share button: previously always linked to plain
  // https://farlo.app regardless of which business was shared. Now must
  // build a real link to that business's visit.farlo.app page.
  group('buildTruckShareMessage', () {
    test('includes a real visit.farlo.app link when slug is present', () {
      final msg = buildTruckShareMessage("Cisco's Grill and Grub", 'ciscos-grill-and-grub');
      expect(msg, contains('https://visit.farlo.app/ciscos-grill-and-grub'));
      expect(msg, contains("Cisco's Grill and Grub"));
    });

    test('falls back to the generic farlo.app link when slug is null', () {
      final msg = buildTruckShareMessage('Some Truck', null);
      expect(msg, contains('https://farlo.app'));
      expect(msg, isNot(contains('visit.farlo.app')));
    });

    test('does not build a broken link with a null-ish slug string', () {
      final msg = buildTruckShareMessage('Some Truck', null);
      expect(msg, isNot(contains('visit.farlo.app/null')));
    });
  });
}

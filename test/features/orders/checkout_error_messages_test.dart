import 'package:flutter_test/flutter_test.dart';
import 'package:farlo/features/orders/utils/checkout_error_messages.dart';

// Founder-reported bug: a truck owner mid-onboarding with no Stripe account
// connected made every consumer see "Your payment may have gone through, but
// we couldn't confirm your order" — even though create-payment-intent
// rejects owner_stripe_not_connected before any Stripe PaymentIntent (and so
// any charge) is ever attempted. OrderCartSheet._pay() now isolates
// createPaymentIntent's errors into their own catch, mapped via this
// function, instead of falling into that generic post-charge message.
void main() {
  group('friendlyCheckoutStartError', () {
    test('maps owner_stripe_not_connected to a setup-in-progress message, not a payment scare', () {
      final msg = friendlyCheckoutStartError(Exception('owner_stripe_not_connected'));
      expect(msg, contains("hasn't finished setting up payments"));
      expect(msg, isNot(contains('payment may have gone through')));
    });

    test('maps truck_subscription_inactive to a not-accepting-orders message', () {
      final msg = friendlyCheckoutStartError(Exception('truck_subscription_inactive'));
      expect(msg, contains('not currently accepting orders'));
    });

    test('maps truck_not_found to a truck-not-found message', () {
      final msg = friendlyCheckoutStartError(Exception('truck_not_found'));
      expect(msg, contains('could not be found'));
    });

    test('maps a stale/mismatched menu item error to an update-your-bag message', () {
      final msg = friendlyCheckoutStartError(Exception('menu item abc123 does not belong to truck xyz789'));
      expect(msg, contains('no longer available'));
    });

    test('maps the below-minimum-amount error to an add-another-item message', () {
      final msg = friendlyCheckoutStartError(Exception('order total is below the minimum chargeable amount'));
      expect(msg, contains('too low to charge'));
    });

    test('falls back to a generic non-alarming message for an unrecognized/network error', () {
      final msg = friendlyCheckoutStartError(Exception('SocketException: Connection reset'));
      expect(msg, contains('Could not start checkout'));
      expect(msg, isNot(contains('payment may have gone through')));
    });
  });
}

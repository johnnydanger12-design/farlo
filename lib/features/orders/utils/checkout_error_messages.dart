// create-payment-intent's server-side rejection codes, thrown client-side as
// `Exception(data['error'])` — mapped here to specific, non-alarming
// messages because these failures happen strictly before any Stripe charge
// is attempted. Extracted into its own pure function (matching this
// codebase's pricing.ts/computeRedirect() pattern) so it's unit-testable
// without mocking Stripe or Supabase.
String friendlyCheckoutStartError(Object e) {
  final message = e.toString();
  if (message.contains('owner_stripe_not_connected')) {
    return "This business hasn't finished setting up payments yet. Please check back later.";
  }
  if (message.contains('truck_subscription_inactive')) {
    return 'This business is not currently accepting orders.';
  }
  if (message.contains('truck_not_found')) {
    return 'This business could not be found. Please try again.';
  }
  if (message.contains('does not belong to truck') ||
      message.contains('one or more menu items were not found')) {
    return 'One or more items in your bag are no longer available. Please update your bag and try again.';
  }
  if (message.contains('order total is below the minimum chargeable amount')) {
    return 'Your order total is too low to charge. Please add another item.';
  }
  return 'Could not start checkout. Please check your connection and try again.';
}

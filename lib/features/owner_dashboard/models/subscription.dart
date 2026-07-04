enum SubscriptionStatus {
  trialing,
  active,
  pastDue,
  canceled;

  // Unrecognized/unexpected values (typos, a future Stripe/RevenueCat status
  // this enum doesn't model yet) must fail closed to `canceled`, not
  // `trialing` — `trialing` grants `hasAccess`, so defaulting to it would
  // silently unlock the paywall for any status string this switch doesn't
  // explicitly know about.
  static SubscriptionStatus fromString(String s) => switch (s) {
        'active' => SubscriptionStatus.active,
        'trialing' => SubscriptionStatus.trialing,
        'past_due' => SubscriptionStatus.pastDue,
        _ => SubscriptionStatus.canceled,
      };
}

class Subscription {
  const Subscription({
    required this.id,
    required this.ownerId,
    required this.status,
    required this.createdAt,
    this.revenuecatCustomerId,
    this.productIdentifier,
    this.currentPeriodEnd,
  });

  final String id;
  final String ownerId;
  final SubscriptionStatus status;

  // True during free trial OR active paid subscription — both grant full access.
  bool get hasAccess =>
      status == SubscriptionStatus.active || status == SubscriptionStatus.trialing;
  final String? revenuecatCustomerId;
  final String? productIdentifier;
  final DateTime? currentPeriodEnd;
  final DateTime createdAt;

  factory Subscription.fromMap(Map<String, dynamic> m) => Subscription(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        status: SubscriptionStatus.fromString(m['status'] as String? ?? 'canceled'),
        revenuecatCustomerId: m['revenuecat_customer_id'] as String?,
        productIdentifier: m['product_identifier'] as String?,
        currentPeriodEnd: m['current_period_end'] == null
            ? null
            : DateTime.parse(m['current_period_end'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

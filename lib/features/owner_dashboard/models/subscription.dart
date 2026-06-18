enum SubscriptionStatus {
  trialing,
  active,
  pastDue,
  canceled;

  static SubscriptionStatus fromString(String s) => switch (s) {
        'active' => SubscriptionStatus.active,
        'past_due' => SubscriptionStatus.pastDue,
        'canceled' => SubscriptionStatus.canceled,
        _ => SubscriptionStatus.trialing,
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
        status: SubscriptionStatus.fromString(m['status'] as String? ?? 'trialing'),
        revenuecatCustomerId: m['revenuecat_customer_id'] as String?,
        productIdentifier: m['product_identifier'] as String?,
        currentPeriodEnd: m['current_period_end'] == null
            ? null
            : DateTime.parse(m['current_period_end'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

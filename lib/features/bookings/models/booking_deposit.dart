enum DepositStatus { requested, paid, refunded }

class BookingDeposit {
  const BookingDeposit({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.notes,
    this.dueDate,
    this.stripePaymentIntentId,
  });

  final String id;
  final String bookingId;
  final double amount;
  final String? notes;
  final DateTime? dueDate;
  final DepositStatus status;
  final String? stripePaymentIntentId;
  final DateTime createdAt;

  factory BookingDeposit.fromMap(Map<String, dynamic> m) => BookingDeposit(
        id: m['id'] as String,
        bookingId: m['booking_id'] as String,
        amount: (m['amount'] as num).toDouble(),
        notes: m['notes'] as String?,
        dueDate: m['due_date'] == null ? null : DateTime.parse(m['due_date'] as String),
        status: _statusFromString(m['status'] as String? ?? 'requested'),
        stripePaymentIntentId: m['stripe_payment_intent_id'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  static DepositStatus _statusFromString(String s) => switch (s) {
        'paid' => DepositStatus.paid,
        'refunded' => DepositStatus.refunded,
        _ => DepositStatus.requested,
      };

  BookingDeposit copyWith({DepositStatus? status}) => BookingDeposit(
        id: id,
        bookingId: bookingId,
        amount: amount,
        notes: notes,
        dueDate: dueDate,
        status: status ?? this.status,
        stripePaymentIntentId: stripePaymentIntentId,
        createdAt: createdAt,
      );
}

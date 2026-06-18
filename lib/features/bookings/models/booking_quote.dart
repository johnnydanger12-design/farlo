enum QuoteType { estimate, invoice }

enum QuoteStatus { sent, accepted, declined, paid }

class BookingQuote {
  const BookingQuote({
    required this.id,
    required this.bookingId,
    required this.type,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.notes,
    this.stripePaymentIntentId,
  });

  final String id;
  final String bookingId;
  final QuoteType type;
  final double amount;
  final String? notes;
  final QuoteStatus status;
  final String? stripePaymentIntentId;
  final DateTime createdAt;

  factory BookingQuote.fromMap(Map<String, dynamic> m) => BookingQuote(
        id: m['id'] as String,
        bookingId: m['booking_id'] as String,
        type: m['type'] == 'invoice' ? QuoteType.invoice : QuoteType.estimate,
        amount: (m['amount'] as num).toDouble(),
        notes: m['notes'] as String?,
        status: _statusFromString(m['status'] as String? ?? 'sent'),
        stripePaymentIntentId: m['stripe_payment_intent_id'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  static QuoteStatus _statusFromString(String s) => switch (s) {
        'accepted' => QuoteStatus.accepted,
        'declined' => QuoteStatus.declined,
        'paid' => QuoteStatus.paid,
        _ => QuoteStatus.sent,
      };

  BookingQuote copyWith({QuoteStatus? status}) => BookingQuote(
        id: id,
        bookingId: bookingId,
        type: type,
        amount: amount,
        notes: notes,
        status: status ?? this.status,
        stripePaymentIntentId: stripePaymentIntentId,
        createdAt: createdAt,
      );
}

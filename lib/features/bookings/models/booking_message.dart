class BookingMessage {
  const BookingMessage({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String bookingId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  factory BookingMessage.fromMap(Map<String, dynamic> map) => BookingMessage(
        id: map['id'] as String,
        bookingId: map['booking_id'] as String,
        senderId: map['sender_id'] as String,
        body: map['body'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

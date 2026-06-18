import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_message.dart';

class MessagingRepository {
  MessagingRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<List<BookingMessage>> fetchMessages(String bookingId) async {
    final rows = await _supabase
        .from('booking_messages')
        .select()
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => BookingMessage.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendMessage({
    required String bookingId,
    required String senderId,
    required String body,
  }) async {
    await _supabase.from('booking_messages').insert({
      'booking_id': bookingId,
      'sender_id': senderId,
      'body': body,
    });
    _invokeMessageNotification(bookingId: bookingId, senderId: senderId);
  }

  static String _prefKey(String bookingId, String userId) =>
      'chat_read_${bookingId}_$userId';

  Future<void> markAsRead(String bookingId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefKey(bookingId, userId), DateTime.now().toUtc().toIso8601String());
  }

  Future<int> fetchUnreadCount(String bookingId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey(bookingId, userId));
    final lastRead = stored != null ? DateTime.tryParse(stored) : null;

    var query = _supabase
        .from('booking_messages')
        .select('id')
        .eq('booking_id', bookingId)
        .neq('sender_id', userId);

    if (lastRead != null) {
      query = query.gt('created_at', lastRead.toUtc().toIso8601String());
    }

    final rows = await query;
    return (rows as List).length;
  }

  void _invokeMessageNotification({
    required String bookingId,
    required String senderId,
  }) {
    () async {
      try {
        await _supabase.functions.invoke(
          'send-message-notification',
          body: {'booking_id': bookingId, 'sender_id': senderId},
        );
      } catch (e) {
        debugPrint('Message notification invoke failed: $e');
      }
    }();
  }
}

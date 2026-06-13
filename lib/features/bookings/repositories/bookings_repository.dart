import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_request.dart';

class BookingsRepository {
  BookingsRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<List<BookingRequest>> fetchOwnerRequests(String truckId) async {
    final rows = await _supabase
        .from('event_booking_requests')
        .select()
        .eq('truck_id', truckId)
        .order('event_date', ascending: true);
    return (rows as List).map((r) => BookingRequest.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> updateRequestStatus(String requestId, String status) async {
    await _supabase
        .from('event_booking_requests')
        .update({'status': status})
        .eq('id', requestId);

    // Notify the requester when the owner accepts or declines.
    if (status == 'accepted' || status == 'declined') {
      _invokeNotification('booking_status_changed', requestId);
    }
  }

  Future<void> submitRequest({
    required String truckId,
    required String requesterId,
    required String contactName,
    required String contactEmail,
    String? contactPhone,
    required DateTime eventDate,
    required String eventTime,
    String? duration,
    int? guestCount,
    required String eventLocation,
    required String eventType,
    String? notes,
  }) async {
    final row = await _supabase
        .from('event_booking_requests')
        .insert({
          'truck_id': truckId,
          'requester_id': requesterId,
          'contact_name': contactName,
          'contact_email': contactEmail,
          'contact_phone': ?contactPhone,
          'event_date': eventDate.toIso8601String().substring(0, 10),
          'event_time': eventTime,
          'duration': ?duration,
          'guest_count': ?guestCount,
          'event_location': eventLocation,
          'event_type': eventType,
          'notes': ?notes,
        })
        .select('id')
        .single();

    // Notify the truck owner — fire-and-forget, don't block the submit.
    _invokeNotification('booking_created', row['id'] as String);
  }

  void _invokeNotification(String action, String bookingId) {
    () async {
      try {
        await _supabase.functions.invoke(
          'send-booking-notification',
          body: {'action': action, 'booking_id': bookingId},
        );
      } catch (e) {
        debugPrint('Notification invoke failed: $e');
      }
    }();
  }
}

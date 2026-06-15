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

  Future<List<BookingRequest>> fetchMyRequests(String userId) async {
    final rows = await _supabase
        .from('event_booking_requests')
        .select('*, food_trucks(name)')
        .eq('requester_id', userId)
        .order('event_date', ascending: false);
    return (rows as List).map((r) => BookingRequest.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> cancelRequest(String requestId) async {
    await _supabase
        .from('event_booking_requests')
        .update({'status': 'cancelled', 'cancelled_by': 'consumer'})
        .eq('id', requestId);
    _invokeNotification('booking_cancelled_by_consumer', requestId);
  }

  Future<BookingRequest> createManualBooking({
    required String truckId,
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
          'status': 'accepted',
        })
        .select('*')
        .single();
    _invokeConfirmationEmail(row['id'] as String);
    return BookingRequest.fromMap(row);
  }

  Future<void> updateRequestStatus(String requestId, String status, {String? cancellationReason}) async {
    final updates = <String, dynamic>{'status': status};
    if (status == 'cancelled') {
      updates['cancelled_by'] = 'owner';
    }
    if (cancellationReason != null && cancellationReason.isNotEmpty) {
      updates['cancellation_reason'] = cancellationReason;
    }
    await _supabase
        .from('event_booking_requests')
        .update(updates)
        .eq('id', requestId);

    // Notify the requester when the owner responds or cancels.
    if (status == 'accepted' || status == 'declined' || status == 'cancelled') {
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

  void _invokeConfirmationEmail(String bookingId) {
    () async {
      try {
        await _supabase.functions.invoke(
          'send-booking-confirmation-email',
          body: {'booking_id': bookingId},
        );
      } catch (e) {
        debugPrint('Confirmation email invoke failed: $e');
      }
    }();
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

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_deposit.dart';
import '../models/booking_quote.dart';
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

  Future<List<BookingRequest>> fetchAcceptedBookingsForMonth(
      String truckId, int year, int month) async {
    final start = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01';
    final endDay = DateTime(year, month + 1, 0).day;
    final end = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${endDay.toString().padLeft(2, '0')}';
    final rows = await _supabase
        .from('event_booking_requests')
        .select()
        .eq('truck_id', truckId)
        .eq('status', 'accepted')
        .gte('event_date', start)
        .lte('event_date', end);
    return (rows as List)
        .map((r) => BookingRequest.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<BookingRequest>> fetchMyRequests(String userId) async {
    final rows = await _supabase
        .from('event_booking_requests')
        .select('*, food_trucks(name, cancellation_policy_hours)')
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
    bool? otherTrucksPresent,
    int? otherTrucksCount,
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
          'other_trucks_present': ?otherTrucksPresent,
          'other_trucks_count': ?otherTrucksCount,
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
    bool? otherTrucksPresent,
    int? otherTrucksCount,
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
          'other_trucks_present': ?otherTrucksPresent,
          'other_trucks_count': ?otherTrucksCount,
        })
        .select('id')
        .single();

    // Notify the truck owner — fire-and-forget, don't block the submit.
    _invokeNotification('booking_created', row['id'] as String);
  }

  // ── Quotes (estimates & invoices) ──────────────────────────────────────────

  Future<List<BookingQuote>> fetchQuotes(String bookingId) async {
    final rows = await _supabase
        .from('booking_quotes')
        .select()
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => BookingQuote.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<BookingQuote> sendEstimate(String bookingId, double amount, String? notes) async {
    final row = await _supabase
        .from('booking_quotes')
        .insert({
          'booking_id': bookingId,
          'type': 'estimate',
          'amount': amount,
          'notes': notes,
        })
        .select()
        .single();
    _invokeNotification('estimate_sent', bookingId);
    return BookingQuote.fromMap(row);
  }

  Future<void> respondToEstimate(String quoteId, String bookingId, bool accepted) async {
    await _supabase
        .from('booking_quotes')
        .update({'status': accepted ? 'accepted' : 'declined'})
        .eq('id', quoteId);
    _invokeNotificationWithExtra(
      'estimate_responded',
      bookingId,
      {'accepted': accepted.toString()},
    );
  }

  Future<BookingQuote> sendInvoice(String bookingId, double amount, String? notes) async {
    final row = await _supabase
        .from('booking_quotes')
        .insert({
          'booking_id': bookingId,
          'type': 'invoice',
          'amount': amount,
          'notes': notes,
        })
        .select()
        .single();
    _invokeNotification('invoice_sent', bookingId);
    return BookingQuote.fromMap(row);
  }

  // ── Deposits ────────────────────────────────────────────────────────────────

  Future<BookingDeposit?> fetchDeposit(String bookingId) async {
    final row = await _supabase
        .from('booking_deposits')
        .select()
        .eq('booking_id', bookingId)
        .maybeSingle();
    if (row == null) return null;
    return BookingDeposit.fromMap(row);
  }

  Future<BookingDeposit> requestDeposit(
    String bookingId,
    double amount,
    String? notes,
    DateTime? dueDate,
  ) async {
    final row = await _supabase
        .from('booking_deposits')
        .insert({
          'booking_id': bookingId,
          'amount': amount,
          'notes': notes,
          'due_date': dueDate?.toIso8601String().substring(0, 10),
        })
        .select()
        .single();
    _invokeNotification('deposit_requested', bookingId);
    return BookingDeposit.fromMap(row);
  }

  // ── Payments ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createBookingPaymentIntent({
    required String type,
    required String recordId,
    required String bookingId,
    required double amount,
  }) async {
    final amountCents = (amount * 100).round();
    final res = await _supabase.functions.invoke(
      'create-booking-payment-intent',
      body: {
        'type': type,
        'record_id': recordId,
        'booking_id': bookingId,
        'amount_cents': amountCents,
      },
    );
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return data;
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

  void _invokeNotificationWithExtra(
    String action,
    String bookingId,
    Map<String, String> extra,
  ) {
    () async {
      try {
        await _supabase.functions.invoke(
          'send-booking-notification',
          body: {'action': action, 'booking_id': bookingId, ...extra},
        );
      } catch (e) {
        debugPrint('Notification invoke failed: $e');
      }
    }();
  }
}

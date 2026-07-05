import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/booking_deposit.dart';
import '../models/booking_quote.dart';

// ARCH-1 (code-quality.md §2.14, REMEDIATION_STATE.md's scoped-down definition):
// isolates BookingsRepository's quote/deposit raw Supabase I/O behind an
// injectable interface, so the estimate/invoice/deposit orchestration logic
// can be unit-tested against a mock without replicating Supabase's fluent
// query-builder chain in a test double.

abstract class BookingFinancialsDataSource {
  Future<List<BookingQuote>> fetchQuotes(String bookingId);

  Future<BookingQuote> insertQuote({
    required String bookingId,
    required String type,
    required double amount,
    String? notes,
  });

  Future<void> updateQuoteStatus(String quoteId, String status);

  Future<BookingDeposit?> fetchDeposit(String bookingId);

  Future<BookingDeposit> insertDeposit({
    required String bookingId,
    required double amount,
    String? notes,
    DateTime? dueDate,
  });
}

class SupabaseBookingFinancialsDataSource implements BookingFinancialsDataSource {
  SupabaseBookingFinancialsDataSource(this._supabase);
  final SupabaseClient _supabase;

  @override
  Future<List<BookingQuote>> fetchQuotes(String bookingId) async {
    final rows = await _supabase
        .from('booking_quotes')
        .select()
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true)
        .withNetworkTimeout;
    return (rows as List)
        .map((r) => BookingQuote.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<BookingQuote> insertQuote({
    required String bookingId,
    required String type,
    required double amount,
    String? notes,
  }) async {
    final row = await _supabase
        .from('booking_quotes')
        .insert({
          'booking_id': bookingId,
          'type': type,
          'amount': amount,
          'notes': notes,
        })
        .select()
        .single()
        .withNetworkTimeout;
    return BookingQuote.fromMap(row);
  }

  @override
  Future<void> updateQuoteStatus(String quoteId, String status) async {
    await _supabase
        .from('booking_quotes')
        .update({'status': status})
        .eq('id', quoteId)
        .withNetworkTimeout;
  }

  @override
  Future<BookingDeposit?> fetchDeposit(String bookingId) async {
    final row = await _supabase
        .from('booking_deposits')
        .select()
        .eq('booking_id', bookingId)
        .maybeSingle()
        .withNetworkTimeout;
    if (row == null) return null;
    return BookingDeposit.fromMap(row);
  }

  @override
  Future<BookingDeposit> insertDeposit({
    required String bookingId,
    required double amount,
    String? notes,
    DateTime? dueDate,
  }) async {
    final row = await _supabase
        .from('booking_deposits')
        .insert({
          'booking_id': bookingId,
          'amount': amount,
          'notes': notes,
          'due_date': dueDate?.toIso8601String().substring(0, 10),
        })
        .select()
        .single()
        .withNetworkTimeout;
    return BookingDeposit.fromMap(row);
  }
}

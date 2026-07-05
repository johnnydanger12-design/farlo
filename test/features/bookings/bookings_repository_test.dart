import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:farlo/features/bookings/models/booking_deposit.dart';
import 'package:farlo/features/bookings/models/booking_quote.dart';
import 'package:farlo/features/bookings/repositories/booking_financials_data_source.dart';
import 'package:farlo/features/bookings/repositories/bookings_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockBookingFinancialsDataSource extends Mock implements BookingFinancialsDataSource {}

BookingQuote _quote({String id = 'q1', QuoteType type = QuoteType.estimate}) => BookingQuote(
      id: id,
      bookingId: 'b1',
      type: type,
      amount: 250.0,
      status: QuoteStatus.sent,
      createdAt: DateTime(2026, 1, 1),
    );

BookingDeposit _deposit({String id = 'd1'}) => BookingDeposit(
      id: id,
      bookingId: 'b1',
      amount: 100.0,
      status: DepositStatus.requested,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockBookingFinancialsDataSource mockFinancials;
  late BookingsRepository repository;

  setUp(() {
    mockFinancials = MockBookingFinancialsDataSource();
    repository = BookingsRepository(MockSupabaseClient(), financialsDataSource: mockFinancials);
  });

  group('sendEstimate / sendInvoice', () {
    // sendEstimate and sendInvoice are near-identical wrappers differing only
    // in the literal 'type' string passed to the data source — a real risk
    // (code-quality.md §2.14's 4th ARCH-2 test target, blocked until ARCH-1
    // introduced BookingFinancialsDataSource as a mockable seam) since a
    // copy-paste slip between the two would silently mislabel every quote.
    test('sendEstimate inserts a quote with type "estimate"', () async {
      final quote = _quote(type: QuoteType.estimate);
      when(() => mockFinancials.insertQuote(
            bookingId: any(named: 'bookingId'),
            type: any(named: 'type'),
            amount: any(named: 'amount'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => quote);

      final result = await repository.sendEstimate('b1', 250.0, 'setup fee included');

      expect(result, same(quote));
      verify(() => mockFinancials.insertQuote(
            bookingId: 'b1',
            type: 'estimate',
            amount: 250.0,
            notes: 'setup fee included',
          )).called(1);
    });

    test('sendInvoice inserts a quote with type "invoice"', () async {
      final quote = _quote(id: 'q2', type: QuoteType.invoice);
      when(() => mockFinancials.insertQuote(
            bookingId: any(named: 'bookingId'),
            type: any(named: 'type'),
            amount: any(named: 'amount'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => quote);

      final result = await repository.sendInvoice('b1', 300.0, null);

      expect(result, same(quote));
      verify(() => mockFinancials.insertQuote(
            bookingId: 'b1',
            type: 'invoice',
            amount: 300.0,
            notes: null,
          )).called(1);
    });
  });

  group('respondToEstimate', () {
    test('maps accepted=true to status "accepted"', () async {
      when(() => mockFinancials.updateQuoteStatus(any(), any())).thenAnswer((_) async {});

      await repository.respondToEstimate('q1', 'b1', true);

      verify(() => mockFinancials.updateQuoteStatus('q1', 'accepted')).called(1);
    });

    test('maps accepted=false to status "declined"', () async {
      when(() => mockFinancials.updateQuoteStatus(any(), any())).thenAnswer((_) async {});

      await repository.respondToEstimate('q1', 'b1', false);

      verify(() => mockFinancials.updateQuoteStatus('q1', 'declined')).called(1);
    });
  });

  group('requestDeposit', () {
    test('passes amount/notes/dueDate through to the data source and returns its result', () async {
      final deposit = _deposit();
      final dueDate = DateTime(2026, 3, 1);
      when(() => mockFinancials.insertDeposit(
            bookingId: any(named: 'bookingId'),
            amount: any(named: 'amount'),
            notes: any(named: 'notes'),
            dueDate: any(named: 'dueDate'),
          )).thenAnswer((_) async => deposit);

      final result = await repository.requestDeposit('b1', 100.0, 'half up front', dueDate);

      expect(result, same(deposit));
      verify(() => mockFinancials.insertDeposit(
            bookingId: 'b1',
            amount: 100.0,
            notes: 'half up front',
            dueDate: dueDate,
          )).called(1);
    });
  });
}

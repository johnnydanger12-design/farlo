import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_deposit.dart';
import '../models/booking_quote.dart';
import '../models/booking_request.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/messaging_repository.dart';

// Realtime pending booking count for a truck — used by owner shell badge + dashboard.
final pendingBookingCountProvider =
    StreamProvider.family<int, String>((ref, truckId) {
  final controller = StreamController<int>();

  Future<void> refresh() async {
    try {
      final data = await Supabase.instance.client
          .from('event_booking_requests')
          .select('id')
          .eq('truck_id', truckId)
          .eq('status', 'pending');
      if (!controller.isClosed) controller.add((data as List).length);
    } catch (_) {}
  }

  refresh();

  final channel = Supabase.instance.client
      .channel('pending_bookings_$truckId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'event_booking_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'truck_id',
          value: truckId,
        ),
        callback: (_) => refresh(),
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  return controller.stream;
});

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(Supabase.instance.client);
});

// Owner-facing: list of booking requests for a given truck, refreshable.
class OwnerBookingRequestsNotifier extends AsyncNotifier<List<BookingRequest>> {
  late String _truckId;

  void setTruckId(String truckId) {
    _truckId = truckId;
  }

  @override
  Future<List<BookingRequest>> build() async => [];

  Future<void> load(String truckId) async {
    _truckId = truckId;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(bookingsRepositoryProvider).fetchOwnerRequests(_truckId),
    );
  }

  Future<void> addManual({
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
    final booking = await ref.read(bookingsRepositoryProvider).createManualBooking(
      truckId: truckId,
      contactName: contactName,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      eventDate: eventDate,
      eventTime: eventTime,
      duration: duration,
      guestCount: guestCount,
      eventLocation: eventLocation,
      eventType: eventType,
      notes: notes,
      otherTrucksPresent: otherTrucksPresent,
      otherTrucksCount: otherTrucksCount,
    );
    final current = state.asData?.value ?? [];
    state = AsyncData([booking, ...current]);
  }

  Future<void> updateStatus(String requestId, String status, {String? cancellationReason}) async {
    await ref.read(bookingsRepositoryProvider).updateRequestStatus(requestId, status, cancellationReason: cancellationReason);
    final current = state.asData?.value ?? [];
    state = AsyncData(
      current.map((r) => r.id == requestId ? _withStatus(r, status, cancellationReason: cancellationReason) : r).toList(),
    );
  }

  BookingRequest _withStatus(BookingRequest r, String status, {String? cancellationReason}) => BookingRequest(
        id: r.id,
        truckId: r.truckId,
        truckName: r.truckName,
        requesterId: r.requesterId,
        contactName: r.contactName,
        contactEmail: r.contactEmail,
        contactPhone: r.contactPhone,
        eventDate: r.eventDate,
        eventTime: r.eventTime,
        duration: r.duration,
        guestCount: r.guestCount,
        eventLocation: r.eventLocation,
        eventType: r.eventType,
        notes: r.notes,
        status: status,
        cancellationReason: cancellationReason ?? r.cancellationReason,
        cancelledBy: status == 'cancelled' ? 'owner' : r.cancelledBy,
        createdAt: r.createdAt,
        otherTrucksPresent: r.otherTrucksPresent,
        otherTrucksCount: r.otherTrucksCount,
      );
}

final ownerBookingRequestsProvider = AsyncNotifierProvider<OwnerBookingRequestsNotifier, List<BookingRequest>>(
  OwnerBookingRequestsNotifier.new,
);

// ─── Consumer: my submitted requests ─────────────────────────────────────────

class MyBookingRequestsNotifier extends AsyncNotifier<List<BookingRequest>> {
  @override
  Future<List<BookingRequest>> build() async => [];

  Future<void> load(String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(bookingsRepositoryProvider).fetchMyRequests(userId),
    );
  }

  Future<void> cancel(String requestId) async {
    await ref.read(bookingsRepositoryProvider).cancelRequest(requestId);
    final current = state.asData?.value ?? [];
    state = AsyncData(
      current.map((r) => r.id == requestId ? _withStatus(r, 'cancelled') : r).toList(),
    );
  }

  BookingRequest _withStatus(BookingRequest r, String status) => BookingRequest(
        id: r.id,
        truckId: r.truckId,
        truckName: r.truckName,
        requesterId: r.requesterId,
        contactName: r.contactName,
        contactEmail: r.contactEmail,
        contactPhone: r.contactPhone,
        eventDate: r.eventDate,
        eventTime: r.eventTime,
        duration: r.duration,
        guestCount: r.guestCount,
        eventLocation: r.eventLocation,
        eventType: r.eventType,
        notes: r.notes,
        status: status,
        cancellationReason: r.cancellationReason,
        cancelledBy: status == 'cancelled' ? 'consumer' : r.cancelledBy,
        createdAt: r.createdAt,
        otherTrucksPresent: r.otherTrucksPresent,
        otherTrucksCount: r.otherTrucksCount,
      );
}

final myBookingRequestsProvider = AsyncNotifierProvider<MyBookingRequestsNotifier, List<BookingRequest>>(
  MyBookingRequestsNotifier.new,
);

// Unread message count per booking for the current user — used for chat badges.
// "Unread" = messages from the other party sent after the last time this user opened the chat.
final bookingMessageCountProvider =
    FutureProvider.autoDispose.family<int, (String, String)>((ref, args) async {
  final (bookingId, userId) = args;
  return MessagingRepository(Supabase.instance.client)
      .fetchUnreadCount(bookingId, userId);
});

// ─── Financial: quotes (estimates & invoices) ─────────────────────────────────

final bookingQuotesProvider =
    FutureProvider.autoDispose.family<List<BookingQuote>, String>((ref, bookingId) {
  return ref.read(bookingsRepositoryProvider).fetchQuotes(bookingId);
});

// ─── Financial: deposit ───────────────────────────────────────────────────────

final bookingDepositProvider =
    FutureProvider.autoDispose.family<BookingDeposit?, String>((ref, bookingId) {
  return ref.read(bookingsRepositoryProvider).fetchDeposit(bookingId);
});

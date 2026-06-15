import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/booking_request.dart';
import '../repositories/bookings_repository.dart';

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
      );
}

final myBookingRequestsProvider = AsyncNotifierProvider<MyBookingRequestsNotifier, List<BookingRequest>>(
  MyBookingRequestsNotifier.new,
);

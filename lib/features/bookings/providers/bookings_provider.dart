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

  Future<void> updateStatus(String requestId, String status) async {
    await ref.read(bookingsRepositoryProvider).updateRequestStatus(requestId, status);
    final current = state.asData?.value ?? [];
    state = AsyncData(
      current.map((r) => r.id == requestId ? _withStatus(r, status) : r).toList(),
    );
  }

  BookingRequest _withStatus(BookingRequest r, String status) => BookingRequest(
        id: r.id,
        truckId: r.truckId,
        requesterId: r.requesterId,
        contactName: r.contactName,
        contactEmail: r.contactEmail,
        contactPhone: r.contactPhone,
        eventDate: r.eventDate,
        eventTime: r.eventTime,
        guestCount: r.guestCount,
        eventLocation: r.eventLocation,
        eventType: r.eventType,
        notes: r.notes,
        status: status,
        createdAt: r.createdAt,
      );
}

final ownerBookingRequestsProvider = AsyncNotifierProvider<OwnerBookingRequestsNotifier, List<BookingRequest>>(
  OwnerBookingRequestsNotifier.new,
);

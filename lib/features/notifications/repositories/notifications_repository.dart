import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_notification.dart';

class NotificationsRepository {
  NotificationsRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<List<AppNotification>> fetchNotifications(String userId) async {
    final rows = await _supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((r) => AppNotification.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({'read': true})
        .eq('id', notificationId);
  }

  Future<void> markAllRead(String userId) async {
    await _supabase
        .from('notifications')
        .update({'read': true})
        .eq('user_id', userId)
        .eq('read', false);
  }

  Future<void> markBookingNotificationsRead(String userId) async {
    await _supabase
        .from('notifications')
        .update({'read': true})
        .eq('user_id', userId)
        .eq('read', false)
        .inFilter('type', const [
          'booking_created',
          'estimate_responded',
          'deposit_paid',
          'invoice_paid',
          'booking_cancelled_by_consumer',
        ]);
  }

  Future<void> deleteNotification(String notificationId) async {
    await _supabase
        .from('notifications')
        .delete()
        .eq('id', notificationId);
  }

  Stream<List<AppNotification>> streamNotifications(String userId) {
    StreamController<List<AppNotification>>? controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final notifs = await fetchNotifications(userId);
        final c = controller;
        if (c != null && !c.isClosed) c.add(notifs);
      } catch (_) {}
    }

    controller = StreamController<List<AppNotification>>(
      onListen: () {
        refresh();
        channel = _supabase
            .channel('notifications-$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () {
        channel?.unsubscribe();
        channel = null;
        controller?.close();
      },
    );

    return controller.stream;
  }
}

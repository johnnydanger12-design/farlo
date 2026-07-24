import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/extensions/future_timeout.dart';

typedef NotifPrefs = ({
  bool pushEnabled,
  bool openAlert,
  bool announcementAlert,
  bool bookingAlert,
  bool lunchNudgeAlert,
});

const _defaultPrefs = (
  pushEnabled: true,
  openAlert: true,
  announcementAlert: true,
  bookingAlert: true,
  lunchNudgeAlert: true,
);

class NotificationPrefsRepository {
  final _client = Supabase.instance.client;

  Future<NotifPrefs> fetchPrefs() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return _defaultPrefs;

    final data = await _client
        .from('notification_preferences')
        .select('push_enabled, open_alert, announcement_alert, booking_alert, lunch_nudge_alert')
        .eq('user_id', userId)
        .maybeSingle()
        .withNetworkTimeout;

    if (data == null) return _defaultPrefs;
    return (
      pushEnabled: data['push_enabled'] as bool? ?? true,
      openAlert: data['open_alert'] as bool? ?? true,
      announcementAlert: data['announcement_alert'] as bool? ?? true,
      bookingAlert: data['booking_alert'] as bool? ?? true,
      lunchNudgeAlert: data['lunch_nudge_alert'] as bool? ?? true,
    );
  }

  Future<void> updatePrefs({
    bool? pushEnabled,
    bool? openAlert,
    bool? announcementAlert,
    bool? bookingAlert,
    bool? lunchNudgeAlert,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('notification_preferences').upsert(
      {
        'user_id': userId,
        'updated_at': DateTime.now().toIso8601String(),
        'push_enabled': ?pushEnabled,
        'open_alert': ?openAlert,
        'announcement_alert': ?announcementAlert,
        'booking_alert': ?bookingAlert,
        'lunch_nudge_alert': ?lunchNudgeAlert,
      },
      onConflict: 'user_id',
    ).withNetworkTimeout;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotifPrefs = ({bool pushEnabled, bool openAlert});

class NotificationPrefsRepository {
  final _client = Supabase.instance.client;

  Future<NotifPrefs> fetchPrefs() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return (pushEnabled: true, openAlert: true);

    final data = await _client
        .from('notification_preferences')
        .select('push_enabled, open_alert')
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return (pushEnabled: true, openAlert: true);
    return (
      pushEnabled: data['push_enabled'] as bool? ?? true,
      openAlert: data['open_alert'] as bool? ?? true,
    );
  }

  Future<void> updatePrefs({bool? pushEnabled, bool? openAlert}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('notification_preferences').upsert(
      {
        'user_id': userId,
        'updated_at': DateTime.now().toIso8601String(),
        'push_enabled': ?pushEnabled,
        'open_alert': ?openAlert,
      },
      onConflict: 'user_id',
    );
  }
}

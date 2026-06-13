import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/notification_prefs_repository.dart';

export '../repositories/notification_prefs_repository.dart' show NotifPrefs;

class NotificationPrefsNotifier extends AsyncNotifier<NotifPrefs> {
  late final NotificationPrefsRepository _repo;

  @override
  Future<NotifPrefs> build() async {
    _repo = NotificationPrefsRepository();
    return _repo.fetchPrefs();
  }

  Future<void> setPushEnabled(bool value) async {
    final current = state.asData?.value ?? (pushEnabled: true, openAlert: true);
    state = AsyncData((pushEnabled: value, openAlert: current.openAlert));
    await _repo.updatePrefs(pushEnabled: value);
  }

  Future<void> setOpenAlert(bool value) async {
    final current = state.asData?.value ?? (pushEnabled: true, openAlert: true);
    state = AsyncData((pushEnabled: current.pushEnabled, openAlert: value));
    await _repo.updatePrefs(openAlert: value);
  }
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsNotifier, NotifPrefs>(
  NotificationPrefsNotifier.new,
);

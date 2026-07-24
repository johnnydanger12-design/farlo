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

  NotifPrefs get _current =>
      state.asData?.value ??
      (pushEnabled: true, openAlert: true, announcementAlert: true, bookingAlert: true, lunchNudgeAlert: true);

  Future<void> setPushEnabled(bool value) async {
    state = AsyncData((
      pushEnabled: value,
      openAlert: _current.openAlert,
      announcementAlert: _current.announcementAlert,
      bookingAlert: _current.bookingAlert,
      lunchNudgeAlert: _current.lunchNudgeAlert,
    ));
    await _repo.updatePrefs(pushEnabled: value);
  }

  Future<void> setOpenAlert(bool value) async {
    state = AsyncData((
      pushEnabled: _current.pushEnabled,
      openAlert: value,
      announcementAlert: _current.announcementAlert,
      bookingAlert: _current.bookingAlert,
      lunchNudgeAlert: _current.lunchNudgeAlert,
    ));
    await _repo.updatePrefs(openAlert: value);
  }

  Future<void> setAnnouncementAlert(bool value) async {
    state = AsyncData((
      pushEnabled: _current.pushEnabled,
      openAlert: _current.openAlert,
      announcementAlert: value,
      bookingAlert: _current.bookingAlert,
      lunchNudgeAlert: _current.lunchNudgeAlert,
    ));
    await _repo.updatePrefs(announcementAlert: value);
  }

  Future<void> setBookingAlert(bool value) async {
    state = AsyncData((
      pushEnabled: _current.pushEnabled,
      openAlert: _current.openAlert,
      announcementAlert: _current.announcementAlert,
      bookingAlert: value,
      lunchNudgeAlert: _current.lunchNudgeAlert,
    ));
    await _repo.updatePrefs(bookingAlert: value);
  }

  Future<void> setLunchNudgeAlert(bool value) async {
    state = AsyncData((
      pushEnabled: _current.pushEnabled,
      openAlert: _current.openAlert,
      announcementAlert: _current.announcementAlert,
      bookingAlert: _current.bookingAlert,
      lunchNudgeAlert: value,
    ));
    await _repo.updatePrefs(lunchNudgeAlert: value);
  }
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsNotifier, NotifPrefs>(
  NotificationPrefsNotifier.new,
);

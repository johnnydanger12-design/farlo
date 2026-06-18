import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/app_notification.dart';
import '../repositories/notifications_repository.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(Supabase.instance.client);
});

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(authProvider).asData?.value;
  if (user == null) return const Stream.empty();
  return ref.read(notificationsRepositoryProvider).streamNotifications(user.id);
});

final unreadNotificationsCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).asData?.value.where((n) => !n.read).length ?? 0;
});

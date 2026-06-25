import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the current user receives announcements from a specific truck.
/// Defaults to true (opted in) if no preference row exists.
class AnnouncementPrefNotifier extends AsyncNotifier<bool> {
  AnnouncementPrefNotifier(this._truckId);
  final String _truckId;

  @override
  Future<bool> build() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return true;
    final row = await Supabase.instance.client
        .from('follower_notification_preferences')
        .select('announcements_enabled')
        .eq('follower_id', userId)
        .eq('truck_id', _truckId)
        .maybeSingle();
    // No row = opted in by default
    return (row?['announcements_enabled'] as bool?) ?? true;
  }

  Future<void> toggle() async {
    final current = state.asData?.value ?? true;
    final next    = !current;
    state = AsyncData(next); // optimistic

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('follower_notification_preferences')
          .upsert({
            'follower_id'         : userId,
            'truck_id'            : _truckId,
            'announcements_enabled': next,
            'updated_at'          : DateTime.now().toIso8601String(),
          });
    } catch (_) {
      state = AsyncData(current); // revert on failure
    }
  }
}

final announcementPrefProvider = AsyncNotifierProvider.family<
    AnnouncementPrefNotifier, bool, String>(
  (truckId) => AnnouncementPrefNotifier(truckId),
);

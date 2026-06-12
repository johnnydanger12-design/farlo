import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subscription.dart';

class SubscriptionRepository {
  const SubscriptionRepository(this._client);

  final SupabaseClient _client;

  Future<Subscription?> fetchForOwner(String ownerId) async {
    final row = await _client
        .from('subscriptions')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    if (row == null) return null;
    return Subscription.fromMap(row);
  }
}

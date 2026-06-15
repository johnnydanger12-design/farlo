import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_provider.dart';

class TransferInfo {
  const TransferInfo({
    required this.id,
    required this.truckId,
    required this.truckName,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserEmail,
    required this.expiresAt,
  });

  final String id;
  final String truckId;
  final String truckName;
  final String otherUserId;
  final String otherUserName;
  final String otherUserEmail;
  final DateTime expiresAt;
}

// Pending transfer where the current user is the recipient.
final incomingTransferProvider = FutureProvider.autoDispose<TransferInfo?>((ref) async {
  final user = ref.watch(authProvider).asData?.value;
  if (user == null) return null;

  final supabase = Supabase.instance.client;

  final transfer = await supabase
      .from('truck_transfers')
      .select('id, truck_id, from_owner_id, expires_at')
      .eq('to_user_id', user.id)
      .eq('status', 'pending')
      .maybeSingle();

  if (transfer == null) return null;

  final expiresAt = DateTime.parse(transfer['expires_at'] as String);
  if (expiresAt.isBefore(DateTime.now())) return null;

  final truckId = transfer['truck_id'] as String;
  final fromOwnerId = transfer['from_owner_id'] as String;

  final truck = await supabase
      .from('food_trucks')
      .select('name')
      .eq('id', truckId)
      .single();

  final fromOwner = await supabase
      .from('profiles')
      .select('display_name, email')
      .eq('id', fromOwnerId)
      .single();

  return TransferInfo(
    id: transfer['id'] as String,
    truckId: truckId,
    truckName: truck['name'] as String,
    otherUserId: fromOwnerId,
    otherUserName: fromOwner['display_name'] as String,
    otherUserEmail: fromOwner['email'] as String,
    expiresAt: expiresAt,
  );
});

// Pending transfer where the current user (owner) is the sender.
final outgoingTransferProvider = FutureProvider.autoDispose<TransferInfo?>((ref) async {
  final user = ref.watch(authProvider).asData?.value;
  if (user == null || !user.isOwner) return null;

  final supabase = Supabase.instance.client;

  final transfer = await supabase
      .from('truck_transfers')
      .select('id, truck_id, to_user_id, expires_at')
      .eq('from_owner_id', user.id)
      .eq('status', 'pending')
      .maybeSingle();

  if (transfer == null) return null;

  final toUserId = transfer['to_user_id'] as String;

  final truck = await supabase
      .from('food_trucks')
      .select('name')
      .eq('id', transfer['truck_id'] as String)
      .single();

  final toUser = await supabase
      .from('profiles')
      .select('display_name, email')
      .eq('id', toUserId)
      .single();

  return TransferInfo(
    id: transfer['id'] as String,
    truckId: transfer['truck_id'] as String,
    truckName: truck['name'] as String,
    otherUserId: toUserId,
    otherUserName: toUser['display_name'] as String,
    otherUserEmail: toUser['email'] as String,
    expiresAt: DateTime.parse(transfer['expires_at'] as String),
  );
});

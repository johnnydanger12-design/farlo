import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../providers/transfer_provider.dart';

class TransferTruckSheet extends ConsumerStatefulWidget {
  const TransferTruckSheet({super.key});

  @override
  ConsumerState<TransferTruckSheet> createState() => _TransferTruckSheetState();
}

class _TransferTruckSheetState extends ConsumerState<TransferTruckSheet> {
  final _emailCtrl = TextEditingController();
  bool _searching = false;
  bool _submitting = false;
  Map<String, dynamic>? _recipient;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _findRecipient() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;

    setState(() { _searching = true; _error = null; _recipient = null; });

    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;

      // profiles is self-read-only via RLS — email lookup for the transfer
      // recipient goes through the narrow find_profile_by_email RPC instead.
      final rows = (await supabase
              .rpc('find_profile_by_email', params: {'p_email': email}) as List)
          .cast<Map<String, dynamic>>();
      final result = rows.isEmpty ? null : {...rows.first, 'email': email};

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _error = 'No account found with that email. The new owner must sign up for Farlo first.';
        });
      } else if ((result['id'] as String) == currentUserId) {
        setState(() { _error = 'You can\'t transfer your business to yourself.'; });
      } else {
        setState(() { _recipient = result; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Something went wrong. Please try again.'; });
    } finally {
      if (mounted) setState(() { _searching = false; });
    }
  }

  Future<void> _sendTransfer(String truckId) async {
    if (_recipient == null) return;
    setState(() { _submitting = true; _error = null; });

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('truck_transfers').insert({
        'truck_id': truckId,
        'from_owner_id': supabase.auth.currentUser!.id,
        'to_user_id': _recipient!['id'],
      });

      if (mounted) {
        ref.invalidate(outgoingTransferProvider);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        setState(() {
          _error = msg.contains('one_pending_transfer_per_truck')
              ? 'A pending transfer already exists. Cancel it first.'
              : 'Failed to send transfer request. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final truck = ref.watch(ownerTruckProvider).asData?.value;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Transfer Business Ownership',
                style: AppTextStyles.heading3,
                textAlign: TextAlign.center,
              ),
              if (truck != null) ...[
                const SizedBox(height: 4),
                Text(truck.name, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
              ],
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'This permanently transfers ownership of the business and its active subscription to the new owner. Your account will become a consumer account. This cannot be undone once accepted.\n\nImportant: cancel your subscription in ${Platform.isIOS ? 'App Store' : 'Google Play'} Settings → Subscriptions to stop being charged.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_recipient == null) ...[
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _findRecipient(),
                  decoration: const InputDecoration(
                    labelText: 'New owner\'s email address',
                    hintText: 'email@example.com',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _searching ? null : _findRecipient,
                  child: _searching
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Find Account'),
                ),
              ] else ...[
                _RecipientCard(recipient: _recipient!),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : () => setState(() { _recipient = null; _error = null; _emailCtrl.clear(); }),
                        child: const Text('Change'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                        onPressed: (truck == null || _submitting)
                            ? null
                            : () => _sendTransfer(truck.id),
                        child: _submitting
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Send Request'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipientCard extends StatelessWidget {
  const _RecipientCard({required this.recipient});
  final Map<String, dynamic> recipient;

  @override
  Widget build(BuildContext context) {
    final name = recipient['display_name'] as String;
    final email = recipient['email'] as String;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.label),
                Text(email, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
        ],
      ),
    );
  }
}

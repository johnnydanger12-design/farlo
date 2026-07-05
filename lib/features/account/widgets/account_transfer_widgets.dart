import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/business_type_picker.dart';
import '../../bookings/widgets/places_autocomplete_field.dart';
import '../providers/transfer_provider.dart';

// ARCH-4 (code-quality.md): extracted out of the 1452-line account_screen.dart.

class IncomingTransferCard extends StatelessWidget {
  const IncomingTransferCard({
    super.key,
    required this.transfer,
    required this.onAccept,
    required this.onDecline,
  });

  final TransferInfo transfer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final daysLeft = transfer.expiresAt.difference(DateTime.now()).inDays;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, color: Theme.of(context).colorScheme.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                'Ownership Transfer Offer',
                style: AppTextStyles.label.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(transfer.truckName, style: AppTextStyles.heading3),
          const SizedBox(height: 2),
          Text(
            'From ${transfer.otherUserName} · Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Includes the active subscription — you\'ll keep the remaining paid period and manage your own billing after it ends.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OutgoingTransferBanner extends StatelessWidget {
  const OutgoingTransferBanner({super.key, required this.transfer, required this.onCancel});

  final TransferInfo transfer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final daysLeft = transfer.expiresAt.difference(DateTime.now()).inDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending transfer to ${transfer.otherUserName}',
                  style: AppTextStyles.label,
                ),
                Text(
                  'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: AppColors.error, padding: EdgeInsets.zero),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ─── Upgrade to owner sheet ───────────────────────────────────────────────────

class UpgradeToOwnerSheet extends StatefulWidget {
  const UpgradeToOwnerSheet({super.key, required this.ref});
  final WidgetRef ref;

  @override
  State<UpgradeToOwnerSheet> createState() => _UpgradeToOwnerSheetState();
}

class _UpgradeToOwnerSheetState extends State<UpgradeToOwnerSheet> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _businessType = 'mobile';
  double? _lat;
  double? _lng;
  bool _loading = false;
  String? _error;

  bool get _isFixed => _businessType == 'fixed';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name for your business.');
      return;
    }
    if (_isFixed && _lat == null) {
      setState(() => _error = 'Select your business address from the suggestions.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.ref.read(authProvider.notifier).upgradeToOwner(
        name,
        businessType: _businessType,
        address: _isFixed ? _addressCtrl.text.trim() : null,
        lat: _isFixed ? _lat : null,
        lng: _isFixed ? _lng : null,
      );
    } catch (e) {
      if (mounted) setState(() { _error = 'Something went wrong. Please try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Start a Business', style: AppTextStyles.heading3),
            const SizedBox(height: 4),
            Text(
              'Create an owner account. You\'ll be able to set up your profile, open for business on the map, and accept orders.',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Business type', style: AppTextStyles.label),
            const SizedBox(height: AppSpacing.sm),
            BusinessTypePicker(
              selected: _businessType,
              onChanged: (t) => setState(() {
                _businessType = t;
                _lat = null;
                _lng = null;
                _addressCtrl.clear();
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Business name',
                hintText: 'e.g. Smoky\'s BBQ',
              ),
              onSubmitted: _isFixed ? null : (_) => _submit(),
            ),
            if (_isFixed) ...[
              const SizedBox(height: AppSpacing.md),
              PlacesAutocompleteField(
                controller: _addressCtrl,
                label: '* Business address',
                onCoordinatesSelected: (lat, lng) => setState(() { _lat = lat; _lng = lng; }),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Owner Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

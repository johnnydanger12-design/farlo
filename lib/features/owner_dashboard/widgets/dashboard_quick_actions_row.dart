import 'package:flutter/material.dart';
import '../../../core/constants/app_spacing.dart';

class DashboardQuickActionsRow extends StatelessWidget {
  const DashboardQuickActionsRow({
    super.key,
    required this.onAnnouncement,
    required this.onShare,
  });

  final VoidCallback onAnnouncement;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onAnnouncement,
            icon: const Icon(Icons.campaign_outlined, size: 18),
            label: const Text('Announce'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_outlined, size: 18),
            label: const Text('Share Profile'),
          ),
        ),
      ],
    );
  }
}

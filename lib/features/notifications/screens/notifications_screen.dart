import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../../bookings/screens/booking_chat_screen.dart';
import '../../employees/screens/employee_dashboard_screen.dart';
import '../../reviews/providers/reviews_provider.dart';
import '../models/app_notification.dart';
import '../providers/notifications_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider);
    final user = ref.watch(authProvider).asData?.value;
    final hasUnread = notifsAsync.asData?.value.any((n) => !n.read) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: AppTextStyles.heading3),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () {
                if (user != null) {
                  ref.read(notificationsRepositoryProvider).markAllRead(user.id);
                }
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: notifsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_outlined,
                      size: 56, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  const Text('No notifications yet',
                      style: TextStyle(color: AppColors.textHint, fontSize: 15)),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) {
              final n = items[i];
              return Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) {
                  ref.read(notificationsRepositoryProvider).deleteNotification(n.id);
                },
                child: _NotificationTile(
                  notification: n,
                  onTap: () => _handleTap(context, ref, n, user?.isOwner ?? false),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    AppNotification n,
    bool isOwner,
  ) async {
    if (!n.read) {
      ref.read(notificationsRepositoryProvider).markRead(n.id);
    }
    switch (n.type) {
      case 'booking_created':
      case 'booking_cancelled_by_consumer':
        context.go('/owner-bookings');
      case 'booking_accepted':
      case 'booking_declined':
      case 'booking_cancelled_by_owner':
        if (isOwner) {
          context.go('/owner-bookings');
        } else {
          // Route under notifications branch so back → Notifications, not Account
          context.go('/notifications/my-requests');
        }
      case 'new_message':
        if (n.relatedId != null) {
          final senderName = n.body.split(' sent you').first;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookingChatScreen(
                bookingId: n.relatedId!,
                title: senderName,
                subtitle: n.body,
              ),
            ),
          );
        }
      case 'new_review':
        if (n.relatedId != null) {
          ref.invalidate(truckReviewsProvider(n.relatedId!));
          context.go('/dashboard/truck/${n.relatedId}', extra: true);
        }
      case 'review_response':
        if (n.relatedId != null) {
          ref.invalidate(truckReviewsProvider(n.relatedId!));
          context.go('/map/truck/${n.relatedId}', extra: true);
        }
      case 'order_placed':
      case 'order_cancelled':
        context.go('/dashboard/orders');
      case 'order_accepted':
      case 'order_ready':
      case 'order_declined':
        // Route under notifications branch so back → Notifications, not Account
        context.go('/notifications/my-orders');
      case 'shift_assigned':
      case 'shift_corrected':
        // Fetch the shift's truck so we can open EmployeeDashboardScreen directly.
        if (n.relatedId != null) {
          try {
            final row = await Supabase.instance.client
                .from('scheduled_shifts')
                .select('truck_id, food_trucks(name)')
                .eq('id', n.relatedId!)
                .single();
            if (!context.mounted) return;
            final truckId   = row['truck_id'] as String;
            final truckName = (row['food_trucks'] as Map?)?['name'] as String? ?? '';
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => EmployeeDashboardScreen(
                  truckId: truckId,
                  truckName: truckName,
                ),
              ),
            );
          } catch (_) {
            if (context.mounted) context.go('/map');
          }
        } else {
          context.go('/map');
        }
      case 'shift_response':
        // Owner: someone responded to a shift assignment.
        context.go('/dashboard');
      case 'open_check':
        context.go(isOwner ? '/dashboard' : '/map');
      case 'announcement':
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) {
            final isLight = Theme.of(ctx).brightness == Brightness.light;
            return Container(
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Theme.of(ctx).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                    Row(
                      children: [
                        Expanded(child: Text(n.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                        IconButton(icon: const Icon(Icons.close), visualDensity: VisualDensity.compact, onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(n.body, style: const TextStyle(fontSize: 15, height: 1.5)),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      default:
        break;
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  IconData get _icon {
    return switch (notification.type) {
      'booking_created' => Icons.event_outlined,
      'booking_accepted' => Icons.check_circle_outline,
      'booking_declined' => Icons.cancel_outlined,
      'booking_cancelled_by_consumer' ||
      'booking_cancelled_by_owner' =>
        Icons.event_busy_outlined,
      'new_message' => Icons.chat_bubble_outline,
      'announcement' => Icons.campaign_outlined,
      'new_review' => Icons.star_outline_rounded,
      'review_response' => Icons.reply_outlined,
      'order_placed' => Icons.shopping_bag_outlined,
      'order_accepted' => Icons.check_circle_outline,
      'order_ready' => Icons.storefront_outlined,
      'order_declined' => Icons.cancel_outlined,
      'order_cancelled' => Icons.remove_shopping_cart_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final unread = !notification.read;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: unread
                        ? primary.withValues(alpha: 0.12)
                        : AppColors.divider.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _icon,
                    size: 20,
                    color: unread ? primary : AppColors.textHint,
                  ),
                ),
                if (unread)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(notification.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: TextStyle(
                      fontSize: 13,
                      color: unread
                          ? Theme.of(context).colorScheme.onSurface
                          : AppColors.textHint,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

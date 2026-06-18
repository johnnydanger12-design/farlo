import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/location_tracking_service.dart';
import '../../../core/push_notification_service.dart';
import '../../account/providers/notification_prefs_provider.dart';
import '../../favorites/repositories/favorites_repository.dart';
import '../../food_trucks/providers/food_truck_provider.dart';
import '../../bookings/models/booking_request.dart';
import '../../bookings/repositories/bookings_repository.dart';
import '../../employees/models/employee_shift.dart';
import '../../employees/models/scheduled_shift.dart';
import '../../employees/providers/employees_provider.dart';
import '../../employees/providers/shifts_provider.dart';
import '../../employees/widgets/assign_shift_sheet.dart';
import '../../employees/widgets/shift_calendar_widget.dart';
import '../../map/models/food_truck.dart';
import '../../../core/widgets/truck_map_pin.dart';
import '../../food_trucks/screens/truck_profile_screen.dart';
import '../../orders/models/order.dart';

// ─── Dashboard-only lightweight providers ─────────────────────────────────────

final _acceptedBookingsForMonthProvider = FutureProvider.family<
    List<BookingRequest>, (String, int, int)>((ref, key) async {
  final (truckId, year, month) = key;
  return BookingsRepository(Supabase.instance.client)
      .fetchAcceptedBookingsForMonth(truckId, year, month);
});

final _activeOrdersProvider =
    FutureProvider.family<List<Order>, String>((ref, truckId) async {
  final data = await Supabase.instance.client
      .from('orders')
      .select(
          'id, truck_id, consumer_id, status, total_price, payment_status,'
          ' pickup_note, stripe_payment_intent_id, created_at, updated_at,'
          ' order_items(*)')
      .eq('truck_id', truckId)
      .inFilter('status', const ['pending', 'accepted', 'ready'])
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => Order.fromMap(e as Map<String, dynamic>))
      .toList();
});

final _profileDisplayNameProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
  final data = await Supabase.instance.client
      .from('profiles')
      .select('display_name')
      .eq('id', userId)
      .maybeSingle();
  return data?['display_name'] as String?;
});

// ─── Main Screen ──────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(ownerTruckProvider);
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: asyncTruck.when(
        loading: () => Center(
          child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary),
        ),
        error: (e, _) =>
            Center(child: Text('Error: $e', style: AppTextStyles.bodySmall)),
        data: (truck) {
          if (truck == null) {
            return const Center(child: Text('No truck found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _QuickActionsRow(
                onAnnouncement: () =>
                    _showAnnouncementSheet(context, truck.id, truck.name),
                onShare: () => _shareTruckProfile(context, truck.name),
              ),
              const SizedBox(height: AppSpacing.md),
              _StatusCard(
                truck: truck,
                currentUserId: currentUserId,
                onGoLive: (val) =>
                    _handleToggle(context, ref, val, truck.name),
              ),
              const SizedBox(height: AppSpacing.md),
              if (truck.isOpen) ...[
                _OrdersWidget(truckId: truck.id),
                const SizedBox(height: AppSpacing.md),
              ],
              _OwnerCalendarSection(truckId: truck.id),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleToggle(
    BuildContext context,
    WidgetRef ref,
    bool isOpen,
    String truckName,
  ) async {
    if (!isOpen) {
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(false);
      LocationTrackingService.instance.stop();
      final prefs = ref.read(notificationPrefsProvider).asData?.value;
      if (prefs?.pushEnabled ?? true) {
        if (prefs?.openAlert ?? true) {
          PushNotificationService.sendTruckClosedAlert(truckName);
        }
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Location permission is required to go live')),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting your location…')),
      );
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      String? address;
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final street = [
            if (p.subThoroughfare?.isNotEmpty ?? false) p.subThoroughfare!,
            if (p.thoroughfare?.isNotEmpty ?? false) p.thoroughfare!,
          ].join(' ');
          final city = p.locality ?? '';
          if (street.isNotEmpty && city.isNotEmpty) {
            address = '$street, $city';
          } else if (city.isNotEmpty) {
            address = city;
          } else if (street.isNotEmpty) {
            address = street;
          }
        }
      } catch (_) {}

      await ref
          .read(ownerTruckProvider.notifier)
          .updateLocation(pos.latitude, pos.longitude, address: address);
      await ref.read(ownerTruckProvider.notifier).setOpenStatus(true);
      LocationTrackingService.instance.start(
        onLocation: ref.read(ownerTruckProvider.notifier).updateLocation,
      );

      final prefs = ref.read(notificationPrefsProvider).asData?.value;
      if (prefs?.pushEnabled ?? true) {
        if (prefs?.openAlert ?? true) {
          PushNotificationService.sendTruckOpenAlert(truckName);
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You\'re live — customers can find you now!'),
            backgroundColor: AppColors.openGreen,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  void _showAnnouncementSheet(
      BuildContext context, String truckId, String truckName) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AnnouncementSheet(truckId: truckId, truckName: truckName),
    );
  }

  void _shareTruckProfile(BuildContext context, String truckName) {
    final box = context.findRenderObject() as RenderBox?;
    Share.share(
      'Check out $truckName on Farlo!\n\n'
      'Find food trucks near you, see their menus, and follow your favorites.\n\n'
      'Download the app → https://farlo.app',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }
}

// ─── Status Card ──────────────────────────────────────────────────────────────

class _StatusCard extends ConsumerWidget {
  const _StatusCard({
    required this.truck,
    required this.currentUserId,
    required this.onGoLive,
  });

  final FoodTruck truck;
  final String currentUserId;
  final void Function(bool) onGoLive;

  bool get _isEmployeeLive =>
      truck.isOpen &&
      truck.openedByUserId != null &&
      truck.openedByUserId != currentUserId;

  String get _locationAge {
    if (!truck.isOpen || truck.locationUpdatedAt == null) return '';
    final diff = DateTime.now().difference(truck.locationUpdatedAt!);
    if (diff.inMinutes < 1) return 'Location updated just now';
    if (diff.inHours < 1) return 'Location updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeName = _isEmployeeLive
        ? ref
            .watch(_profileDisplayNameProvider(truck.openedByUserId!))
            .asData
            ?.value
        : null;
    final firstName = employeeName?.split(' ').first ?? 'Employee';
    final locationAge = _locationAge;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Truck name + logo — tap to view profile
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TruckProfileScreen(truckId: truck.id),
              ),
            ),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: truck.logoUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              truck.logoUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.lunch_dining,
                                color: Theme.of(context).colorScheme.primary,
                                size: 24,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.lunch_dining,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(truck.name, style: AppTextStyles.heading3),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 18, color: AppColors.textHint),
                          ],
                        ),
                        if (locationAge.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(locationAge, style: AppTextStyles.caption),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Mini-map animates in when live
          AnimatedCrossFade(
            firstChild:
                const SizedBox(height: AppSpacing.lg, width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 160,
                  child: truck.latitude != null && truck.longitude != null
                      ? FlutterMap(
                          options: MapOptions(
                            initialCenter:
                                LatLng(truck.latitude!, truck.longitude!),
                            initialZoom: 16,
                            interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  Theme.of(context).brightness == Brightness.dark
                                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.farlo.app',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(truck.latitude!, truck.longitude!),
                                  width: 44,
                                  height: 44,
                                  child: TruckMapPin(
                                    isOpen: truck.isOpen,
                                    logoUrl: truck.logoUrl,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const ColoredBox(
                          color: Color(0xFF1A1A1A),
                          child: Center(
                            child: Text('Location not set',
                                style: TextStyle(color: Colors.white54)),
                          ),
                        ),
                ),
              ),
            ),
            crossFadeState: truck.isOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 350),
          ),

          // Status row: text + toggle or end session
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        truck.isOpen
                            ? (_isEmployeeLive
                                ? '$firstName is Live'
                                : 'You\'re Live')
                            : 'You\'re Offline',
                        style: AppTextStyles.label.copyWith(
                          color: truck.isOpen
                              ? AppColors.openGreen
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        truck.isOpen
                            ? (_isEmployeeLive
                                ? 'Your truck is live on the map'
                                : 'Customers can see you on the map')
                            : 'Flip to go live and share your location',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (_isEmployeeLive)
                  OutlinedButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: isLight ? Colors.white : null,
                          title: const Text('End Session?',
                              textAlign: TextAlign.center),
                          content: Text(
                            'This will take $firstName offline and end their active session.',
                            textAlign: TextAlign.center,
                          ),
                          actionsAlignment: MainAxisAlignment.center,
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('End Session',
                                  style:
                                      TextStyle(color: AppColors.error)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) onGoLive(false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: const Text('End Session'),
                  )
                else
                  Switch(
                    value: truck.isOpen,
                    onChanged: onGoLive,
                    activeThumbColor: AppColors.openGreen,
                    activeTrackColor:
                        AppColors.openGreen.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Orders Widget (hero — shows when truck is live) ──────────────────────────

class _OrdersWidget extends ConsumerStatefulWidget {
  const _OrdersWidget({required this.truckId});
  final String truckId;

  @override
  ConsumerState<_OrdersWidget> createState() => _OrdersWidgetState();
}

class _OrdersWidgetState extends ConsumerState<_OrdersWidget> {
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _ordersChannel = Supabase.instance.client
        .channel('dashboard-orders-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) =>
              ref.invalidate(_activeOrdersProvider(widget.truckId)),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_ordersChannel != null) {
      Supabase.instance.client.removeChannel(_ordersChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(_activeOrdersProvider(widget.truckId));
    final orders = ordersAsync.asData?.value ?? [];
    final incoming = orders.where((o) => o.status == 'pending').toList();
    final inProgress = orders
        .where((o) => o.status == 'accepted' || o.status == 'ready')
        .toList();
    final truck = ref.watch(ownerTruckProvider).asData?.value;
    final ordersAccepting = truck?.ordersAccepting ?? true;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — tappable to go to orders screen
          GestureDetector(
            onTap: () => context.go('/dashboard/orders'),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_long_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Orders', style: AppTextStyles.label)),
                  const Icon(Icons.chevron_right, color: AppColors.textHint),
                ],
              ),
            ),
          ),
          // Accept orders toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.md, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ordersAccepting ? 'Accepting orders' : 'Not accepting orders',
                    style: AppTextStyles.caption.copyWith(
                      color: ordersAccepting
                          ? AppColors.openGreen
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Switch(
                  value: ordersAccepting,
                  onChanged: (_) => ref
                      .read(ownerTruckProvider.notifier)
                      .updateOrdersAccepting(!ordersAccepting),
                  activeThumbColor: AppColors.openGreen,
                  activeTrackColor: AppColors.openGreen.withValues(alpha: 0.4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          // Order rows
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: ordersAsync.isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : orders.isEmpty
                    ? Text('No active orders', style: AppTextStyles.bodySmall)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (incoming.isNotEmpty) ...[
                            _OrderSectionLabel(
                                'Incoming (${incoming.length})'),
                            const SizedBox(height: AppSpacing.sm),
                            ...incoming.map((o) => _DashboardOrderRow(
                                order: o,
                                onTap: () =>
                                    context.go('/dashboard/orders'))),
                          ],
                          if (inProgress.isNotEmpty) ...[
                            if (incoming.isNotEmpty)
                              const SizedBox(height: AppSpacing.md),
                            _OrderSectionLabel(
                                'In Progress (${inProgress.length})'),
                            const SizedBox(height: AppSpacing.sm),
                            ...inProgress.map((o) => _DashboardOrderRow(
                                order: o,
                                onTap: () =>
                                    context.go('/dashboard/orders'))),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _OrderSectionLabel extends StatelessWidget {
  const _OrderSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w700, letterSpacing: 0.8),
    );
  }
}

class _DashboardOrderRow extends StatelessWidget {
  const _DashboardOrderRow({required this.order, required this.onTap});
  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold(0, (sum, i) => sum + i.quantity);
    final statusColor = switch (order.status) {
      'pending' => Colors.orange,
      'accepted' => AppColors.primary,
      'ready' => AppColors.openGreen,
      _ => AppColors.textHint,
    };
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$itemCount item${itemCount != 1 ? 's' : ''} · \$${order.totalPrice.toStringAsFixed(2)}',
                style: AppTextStyles.bodySmall,
              ),
            ),
            Text(
              switch (order.status) {
                'pending' => 'New',
                'accepted' => 'Accepted',
                'ready' => 'Ready',
                _ => order.status,
              },
              style: AppTextStyles.caption
                  .copyWith(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Owner Calendar Section ───────────────────────────────────────────────────

class _OwnerCalendarSection extends ConsumerStatefulWidget {
  const _OwnerCalendarSection({required this.truckId});
  final String truckId;

  @override
  ConsumerState<_OwnerCalendarSection> createState() =>
      _OwnerCalendarSectionState();
}

class _OwnerCalendarSectionState
    extends ConsumerState<_OwnerCalendarSection> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  RealtimeChannel? _workedChannel;
  RealtimeChannel? _scheduledChannel;

  @override
  void initState() {
    super.initState();
    _workedChannel = Supabase.instance.client
        .channel('owner-worked-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'employee_shifts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) => ref.invalidate(
              truckShiftsProvider((widget.truckId, _year, _month))),
        )
        .subscribe();

    _scheduledChannel = Supabase.instance.client
        .channel('owner-scheduled-${widget.truckId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'scheduled_shifts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truckId,
          ),
          callback: (_) => ref.invalidate(
              truckScheduledShiftsProvider((widget.truckId, _year, _month))),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_workedChannel != null) {
      Supabase.instance.client.removeChannel(_workedChannel!);
    }
    if (_scheduledChannel != null) {
      Supabase.instance.client.removeChannel(_scheduledChannel!);
    }
    super.dispose();
  }

  void _showAssignSheet(DateTime date) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AssignShiftSheet(truckId: widget.truckId, initialDate: date),
    ).then((_) => ref.invalidate(
        truckScheduledShiftsProvider((widget.truckId, _year, _month))));
  }

  void _showEditWorkedDialog(EmployeeShift shift) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          EditWorkedShiftDialog(shift: shift, truckId: widget.truckId),
    ).then((_) => ref
        .invalidate(truckShiftsProvider((widget.truckId, _year, _month))));
  }

  Future<void> _confirmDeleteScheduled(ScheduledShift shift) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isLight ? Colors.white : null,
        title: const Text('Delete Shift?', textAlign: TextAlign.center),
        content: const Text(
          'This will remove the scheduled shift and notify the employee.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(employeesRepositoryProvider)
          .deleteScheduledShift(shift.id);
      ref.invalidate(
          truckScheduledShiftsProvider((widget.truckId, _year, _month)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete shift: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.truckId, _year, _month);
    final worked = ref.watch(truckShiftsProvider(key)).asData?.value ?? [];
    final scheduled =
        ref.watch(truckScheduledShiftsProvider(key)).asData?.value ?? [];
    final bookings =
        ref.watch(_acceptedBookingsForMonthProvider(key)).asData?.value ?? [];

    return ShiftCalendarWidget(
      truckId: widget.truckId,
      isOwner: true,
      workedShifts: worked,
      scheduledShifts: scheduled,
      bookings: bookings,
      onMonthChanged: (y, m) => setState(() {
        _year = y;
        _month = m;
      }),
      onEditWorkedShift: _showEditWorkedDialog,
      onAssignShift: _showAssignSheet,
      onDeleteScheduled: _confirmDeleteScheduled,
      onBookingTap: (_) => context.go('/owner-bookings'),
    );
  }
}

// ─── Quick Actions Row ────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
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

// ─── Announcement Sheet ───────────────────────────────────────────────────────

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet({required this.truckId, required this.truckName});
  final String truckId;
  final String truckName;

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _loading = false;

  static const int _maxTitle = 60;
  static const int _maxMessage = 160;

  late final Future<int> _followerCountFuture =
      FavoritesRepository(Supabase.instance.client)
          .fetchFollowerCount(widget.truckId);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (title.isEmpty || message.isEmpty) return;

    setState(() => _loading = true);
    try {
      final sent = await PushNotificationService.sendTruckAnnouncement(
        truckId: widget.truckId,
        title: title,
        message: message,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sent == 0
              ? 'No followers with notifications enabled.'
              : 'Sent to $sent follower${sent == 1 ? '' : 's'}.'),
          backgroundColor: sent > 0 ? AppColors.openGreen : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final titleLen = _titleCtrl.text.length;
    final messageLen = _messageCtrl.text.length;
    final canSend = titleLen > 0 && messageLen > 0 && !_loading;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg + bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text('Send Announcement', style: AppTextStyles.heading3),
              ),
              FutureBuilder<int>(
                future: _followerCountFuture,
                builder: (context, snap) {
                  final count = snap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '$count follower${count == 1 ? '' : 's'}',
                      style: AppTextStyles.caption.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Followers with notifications on will receive this.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _titleCtrl,
            maxLength: _maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. New Menu Item!',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _messageCtrl,
            maxLength: _maxMessage,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Message',
              hintText:
                  'e.g. We just added a new spicy brisket sandwich to our menu!',
              alignLabelWithHint: true,
              counterText: '$messageLen / $_maxMessage',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSend ? _send : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor:
                    Colors.white.withValues(alpha: 0.7),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/truck_map_pin.dart';
import '../../../core/location_tracking_service.dart';
import '../../../core/push_notification_service.dart';
import '../../orders/models/order.dart';
import '../../orders/providers/orders_provider.dart';
import '../../orders/screens/order_queue_screen.dart';
import '../models/employee_shift.dart';
import '../models/scheduled_shift.dart';
import '../providers/employees_provider.dart';
import '../providers/shifts_provider.dart';
import '../widgets/shift_calendar_widget.dart';

class EmployeeDashboardScreen extends ConsumerStatefulWidget {
  const EmployeeDashboardScreen({
    super.key,
    required this.truckId,
    required this.truckName,
  });

  final String truckId;
  final String truckName;

  @override
  ConsumerState<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends ConsumerState<EmployeeDashboardScreen>
    with WidgetsBindingObserver {
  RealtimeChannel? _ordersChannel;
  Timer? _ticker;
  bool _clockingIn = false;
  bool _clockingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ownerOrdersProvider.notifier).load(widget.truckId);
    });
    _ordersChannel = Supabase.instance.client
        .channel('employee-orders-${widget.truckId}')
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
              ref.read(ownerOrdersProvider.notifier).load(widget.truckId),
        )
        .subscribe();
    // Tick every minute to update the shift elapsed timer
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ordersChannel != null) {
      Supabase.instance.client.removeChannel(_ordersChannel!);
    }
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(ownerOrdersProvider.notifier).load(widget.truckId);
    }
  }

  Future<void> _handleClockIn() async {
    if (_clockingIn) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clock In?'),
        content: Text('Start your shift at ${widget.truckName}?'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clock In'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clockingIn = true);
    try {
      final truck =
          ref.read(employeeGoLiveProvider(widget.truckId)).asData?.value;
      final isOwnerLive = truck != null &&
          truck.isOpen &&
          truck.openedByUserId != null &&
          truck.openedByUserId !=
              Supabase.instance.client.auth.currentUser?.id;

      String? address;

      if (!isOwnerLive) {
        // Mode B: employee goes live — get location first
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (!mounted) return;
        if (permission == LocationPermission.deniedForever ||
            permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Location permission is required to go live')));
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Getting your location…')));

        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (!mounted) return;

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

        final notifier =
            ref.read(employeeGoLiveProvider(widget.truckId).notifier);
        await notifier.updateLocation(pos.latitude, pos.longitude,
            address: address);
        await notifier.setOpenStatus(true);
        LocationTrackingService.instance
            .start(onLocation: notifier.updateLocation);

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Truck is live — customers can find you now!'),
            backgroundColor: AppColors.openGreen,
            duration: Duration(seconds: 3),
          ));
        }
      }

      // Record shift start
      await ref
          .read(activeShiftProvider(widget.truckId).notifier)
          .clockIn(locationAddress: address);
      // Reload calendar month
      final now = DateTime.now();
      ref.invalidate(myShiftsProvider((widget.truckId, now.year, now.month)));
      ref.invalidate(myScheduledShiftsProvider((widget.truckId, now.year, now.month)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not clock in: $e')));
      }
    } finally {
      if (mounted) setState(() => _clockingIn = false);
    }
  }

  Future<void> _handleClockOut() async {
    if (_clockingOut) return;

    final truck =
        ref.read(employeeGoLiveProvider(widget.truckId)).asData?.value;
    final isOwnerLive = truck != null &&
        truck.isOpen &&
        truck.openedByUserId != null &&
        truck.openedByUserId !=
            Supabase.instance.client.auth.currentUser?.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clock Out?'),
        content: Text(isOwnerLive
            ? 'End your shift? The truck will stay live on the owner\'s device.'
            : 'End your shift and take the truck offline?'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clock Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clockingOut = true);
    try {
      if (!isOwnerLive) {
        // Mode B: employee was broadcasting — take truck offline
        await ref
            .read(employeeGoLiveProvider(widget.truckId).notifier)
            .setOpenStatus(false);
        LocationTrackingService.instance.stop();
      }
      await ref.read(activeShiftProvider(widget.truckId).notifier).clockOut();
      final now = DateTime.now();
      ref.invalidate(myShiftsProvider((widget.truckId, now.year, now.month)));
      ref.invalidate(myScheduledShiftsProvider((widget.truckId, now.year, now.month)));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not clock out: $e')));
      }
    } finally {
      if (mounted) setState(() => _clockingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTruck = ref.watch(employeeGoLiveProvider(widget.truckId));
    final truck = asyncTruck.asData?.value;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnerLive = truck != null &&
        truck.isOpen &&
        truck.openedByUserId != null &&
        truck.openedByUserId != currentUserId;
    final isTruckLive = truck?.isOpen ?? false;

    final asyncShift = ref.watch(activeShiftProvider(widget.truckId));
    final activeShift = asyncShift.asData?.value;
    final isClockedIn = activeShift?.isActive ?? false;

    // When owner ends employee GPS session mid-shift: stay clocked in (Mode A),
    // but stop GPS — handled already in EmployeeGoLiveNotifier._syncFromRemote.
    // No auto-pop here; employee stays logged in until they clock out.

    return PopScope(
      // Allow back navigation only when not clocked in
      canPop: !isClockedIn,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isClockedIn) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Clock out before leaving your shift.'),
          ));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Shift'),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: !isClockedIn,
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _StatusCard(
              truck: truck,
              truckName: widget.truckName,
              isClockedIn: isClockedIn,
              isTruckLive: isTruckLive,
              isOwnerLive: isOwnerLive,
              activeShift: activeShift,
              isLoading: _clockingIn || _clockingOut || asyncTruck.isLoading,
              onClockIn: _handleClockIn,
              onClockOut: _handleClockOut,
            ),
            if (isClockedIn && isTruckLive) ...[
              const SizedBox(height: AppSpacing.md),
              _EmployeeOrdersCard(truckId: widget.truckId, truck: truck),
            ],
            const SizedBox(height: AppSpacing.xl),
            _EmployeeCalendarSection(truckId: widget.truckId),
          ],
        ),
      ),
    );
  }
}

// ─── Status Card ─────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.truck,
    required this.truckName,
    required this.isClockedIn,
    required this.isTruckLive,
    required this.isOwnerLive,
    required this.activeShift,
    required this.isLoading,
    required this.onClockIn,
    required this.onClockOut,
  });

  final dynamic truck; // FoodTruck?
  final String truckName;
  final bool isClockedIn;
  final bool isTruckLive;
  final bool isOwnerLive;
  final EmployeeShift? activeShift;
  final bool isLoading;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;

  String _elapsedLabel() {
    if (activeShift == null) return '';
    final d = activeShift!.elapsed;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
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
          // Truck name
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
            child: Text(truckName, style: AppTextStyles.heading3),
          ),

          // Mini-map — visible whenever the truck is live (owner or employee)
          AnimatedCrossFade(
            firstChild:
                const SizedBox(height: AppSpacing.lg, width: double.infinity),
            secondChild: truck != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 160,
                        child: truck.latitude != null && truck.longitude != null
                            ? FlutterMap(
                                options: MapOptions(
                                  initialCenter: LatLng(truck.latitude!, truck.longitude!),
                                  initialZoom: 16,
                                  interactionOptions: const InteractionOptions(
                                      flags: InteractiveFlag.none),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: isLight
                                        ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                                        : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
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
                  )
                : const SizedBox(height: AppSpacing.lg, width: double.infinity),
            crossFadeState: isTruckLive
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 350),
          ),

          // Status row
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isClockedIn
                                ? (isOwnerLive
                                    ? 'Owner is Live'
                                    : 'You\'re Clocked In')
                                : 'Not Clocked In',
                            style: AppTextStyles.label.copyWith(
                              color: isClockedIn
                                  ? AppColors.openGreen
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isClockedIn
                                ? (isOwnerLive
                                    ? 'Location broadcasting from owner\'s device'
                                    : 'Truck is live — customers can see you')
                                : 'Clock in to start your shift',
                            style: AppTextStyles.caption,
                          ),
                          if (isClockedIn && activeShift != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Shift time: ${_elapsedLabel()}',
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: isLoading
                      ? const Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : isClockedIn
                          ? FilledButton(
                              onPressed: onClockOut,
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.error),
                              child: const Text('Clock Out'),
                            )
                          : FilledButton(
                              onPressed: onClockIn,
                              child: const Text('Clock In'),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Employee Orders Card ─────────────────────────────────────────────────────

class _EmployeeOrdersCard extends ConsumerWidget {
  const _EmployeeOrdersCard({required this.truckId, required this.truck});
  final String truckId;
  final dynamic truck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ownerOrdersProvider);
    final orders = ordersAsync.asData?.value ?? [];
    final incoming = orders.where((o) => o.status == 'pending').toList();
    final inProgress = orders
        .where((o) => o.status == 'accepted' || o.status == 'ready')
        .toList();
    final ordersAccepting = (truck?.ordersAccepting as bool?) ?? true;

    void openQueue() => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => OrderQueueScreen(truckId: truckId)),
        );

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
          // Header — tappable to open full order queue
          GestureDetector(
            onTap: openQueue,
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
                        color: Theme.of(context).colorScheme.primary, size: 20),
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
                      .read(employeeGoLiveProvider(truckId).notifier)
                      .updateOrdersAccepting(!ordersAccepting),
                  activeThumbColor: AppColors.openGreen,
                  activeTrackColor: AppColors.openGreen.withValues(alpha: 0.4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          // Compact order rows
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
                : (incoming.isEmpty && inProgress.isEmpty)
                    ? Text('No active orders', style: AppTextStyles.bodySmall)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (incoming.isNotEmpty) ...[
                            _SectionHeader('Incoming (${incoming.length})'),
                            const SizedBox(height: AppSpacing.sm),
                            ...incoming.map((o) =>
                                _CompactOrderRow(order: o, onTap: openQueue)),
                          ],
                          if (inProgress.isNotEmpty) ...[
                            if (incoming.isNotEmpty)
                              const SizedBox(height: AppSpacing.md),
                            _SectionHeader('In Progress (${inProgress.length})'),
                            const SizedBox(height: AppSpacing.sm),
                            ...inProgress.map((o) =>
                                _CompactOrderRow(order: o, onTap: openQueue)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Employee Calendar Section ────────────────────────────────────────────────

class _EmployeeCalendarSection extends ConsumerStatefulWidget {
  const _EmployeeCalendarSection({required this.truckId});
  final String truckId;

  @override
  ConsumerState<_EmployeeCalendarSection> createState() =>
      _EmployeeCalendarSectionState();
}

class _EmployeeCalendarSectionState
    extends ConsumerState<_EmployeeCalendarSection> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  Future<void> _handleRespond(ScheduledShift shift, String status) async {
    try {
      await ref
          .read(employeesRepositoryProvider)
          .respondToScheduledShift(shiftId: shift.id, status: status);
      ref.invalidate(myScheduledShiftsProvider(
          (widget.truckId, shift.scheduledStart.year, shift.scheduledStart.month)));
      // Notify owner of the response
      await PushNotificationService.sendShiftResponse(shift.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update shift: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.truckId, _year, _month);
    final workedAsync = ref.watch(myShiftsProvider(key));
    final scheduledAsync = ref.watch(myScheduledShiftsProvider(key));

    final worked = workedAsync.asData?.value ?? [];
    final scheduled = scheduledAsync.asData?.value ?? [];

    return ShiftCalendarWidget(
      truckId: widget.truckId,
      isOwner: false,
      workedShifts: worked,
      scheduledShifts: scheduled,
      onMonthChanged: (y, m) => setState(() {
        _year = y;
        _month = m;
      }),
      onRespondScheduled: _handleRespond,
    );
  }
}

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
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

class _CompactOrderRow extends StatelessWidget {
  const _CompactOrderRow({required this.order, required this.onTap});
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
              decoration:
                  BoxDecoration(color: statusColor, shape: BoxShape.circle),
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


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee_shift.dart';
import '../models/scheduled_shift.dart';
import 'employees_provider.dart';

// ─── Active shift for the logged-in employee on a specific truck ──────────────
//
// Holds the currently open shift (null = not clocked in).
// clockIn / clockOut mutate state optimistically then persist.

class ActiveShiftNotifier extends AsyncNotifier<EmployeeShift?> {
  ActiveShiftNotifier(this._truckId);
  final String _truckId;

  @override
  Future<EmployeeShift?> build() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;
    final data = await Supabase.instance.client
        .from('employee_shifts')
        .select()
        .eq('employee_id', userId)
        .eq('truck_id', _truckId)
        .filter('clocked_out_at', 'is', null)
        .order('clocked_in_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return EmployeeShift.fromMap(data);
  }

  Future<void> clockIn({String? locationAddress}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final repo = ref.read(employeesRepositoryProvider);
    final shift = await repo.clockIn(
      employeeId: userId,
      truckId: _truckId,
      locationAddress: locationAddress,
    );
    state = AsyncData(shift);
  }

  Future<void> clockOut() async {
    final shift = state.asData?.value;
    if (shift == null) return;
    final repo = ref.read(employeesRepositoryProvider);
    final closed = await repo.clockOut(shift.id);
    state = AsyncData(closed);
  }
}

final activeShiftProvider =
    AsyncNotifierProvider.family<ActiveShiftNotifier, EmployeeShift?, String>(
  (truckId) => ActiveShiftNotifier(truckId),
);

// ─── Employee's worked shifts for a truck, scoped to a calendar month ─────────
// Key: (truckId, year, month)

typedef _ShiftMonthKey = (String, int, int);

class MyShiftsNotifier extends AsyncNotifier<List<EmployeeShift>> {
  MyShiftsNotifier(this._key);
  final _ShiftMonthKey _key;

  @override
  Future<List<EmployeeShift>> build() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final (truckId, year, month) = _key;
    return ref.read(employeesRepositoryProvider).fetchMyShiftsForMonth(
          employeeId: userId,
          truckId: truckId,
          year: year,
          month: month,
        );
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final myShiftsProvider = AsyncNotifierProvider.family<MyShiftsNotifier,
    List<EmployeeShift>, _ShiftMonthKey>(
  (key) => MyShiftsNotifier(key),
);

// ─── Employee's scheduled (assigned) shifts for a month ──────────────────────

class MyScheduledShiftsNotifier extends AsyncNotifier<List<ScheduledShift>> {
  MyScheduledShiftsNotifier(this._key);
  final _ShiftMonthKey _key;

  @override
  Future<List<ScheduledShift>> build() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];
    final (truckId, year, month) = _key;
    return ref.read(employeesRepositoryProvider).fetchMyScheduledShiftsForMonth(
          employeeId: userId,
          truckId: truckId,
          year: year,
          month: month,
        );
  }

  Future<void> respond(String shiftId, String status) async {
    await ref
        .read(employeesRepositoryProvider)
        .respondToScheduledShift(shiftId: shiftId, status: status);
    ref.invalidateSelf();
    await future;
  }
}

final myScheduledShiftsProvider = AsyncNotifierProvider.family<
    MyScheduledShiftsNotifier, List<ScheduledShift>, _ShiftMonthKey>(
  (key) => MyScheduledShiftsNotifier(key),
);

// ─── Owner: all worked shifts for their truck, scoped to a calendar month ─────

class TruckShiftsNotifier extends AsyncNotifier<List<EmployeeShift>> {
  TruckShiftsNotifier(this._key);
  final _ShiftMonthKey _key;

  @override
  Future<List<EmployeeShift>> build() async {
    final (truckId, year, month) = _key;
    return ref
        .read(employeesRepositoryProvider)
        .fetchTruckShiftsForMonth(truckId: truckId, year: year, month: month);
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final truckShiftsProvider = AsyncNotifierProvider.family<TruckShiftsNotifier,
    List<EmployeeShift>, _ShiftMonthKey>(
  (key) => TruckShiftsNotifier(key),
);

// ─── Owner: all scheduled shifts for their truck, scoped to a calendar month ──

class TruckScheduledShiftsNotifier
    extends AsyncNotifier<List<ScheduledShift>> {
  TruckScheduledShiftsNotifier(this._key);
  final _ShiftMonthKey _key;

  @override
  Future<List<ScheduledShift>> build() async {
    final (truckId, year, month) = _key;
    return ref
        .read(employeesRepositoryProvider)
        .fetchScheduledShiftsForMonth(truckId: truckId, year: year, month: month);
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final truckScheduledShiftsProvider = AsyncNotifierProvider.family<
    TruckScheduledShiftsNotifier, List<ScheduledShift>, _ShiftMonthKey>(
  (key) => TruckScheduledShiftsNotifier(key),
);

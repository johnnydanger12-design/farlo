import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/extensions/future_timeout.dart';
import '../../../features/map/models/food_truck.dart';
import '../models/employee_shift.dart';
import '../models/scheduled_shift.dart';
import '../models/truck_employee.dart';

class EmployeesRepository {
  EmployeesRepository(this._supabase);

  final SupabaseClient _supabase;

  // Owner: list all employees for a truck
  Future<List<TruckEmployee>> fetchEmployees(String truckId) async {
    final data = await _supabase
        .from(SupabaseConstants.truckEmployeesTable)
        .select('*, profiles(display_name)')
        .eq('truck_id', truckId)
        .neq('status', 'removed')
        .order('invited_at')
        .withNetworkTimeout;
    return (data as List)
        .map((e) => TruckEmployee.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // Owner: invite employee by email.
  // Returns true if they already had an account (added as active immediately),
  // false if pending until they sign up.
  Future<bool> inviteEmployee(String truckId, String email) async {
    final result = await _supabase.rpc('invite_employee_by_email', params: {
      'p_truck_id': truckId,
      'p_email': email.trim().toLowerCase(),
    }).withNetworkTimeout;
    return (result as Map<String, dynamic>)['already_user'] as bool;
  }

  // Owner: remove employee
  Future<void> removeEmployee(String employeeId) async {
    await _supabase
        .from(SupabaseConstants.truckEmployeesTable)
        .update({'status': 'removed'})
        .eq('id', employeeId)
        .withNetworkTimeout;
  }

  // Employee: claim any pending invites matching this user's email
  Future<void> claimPendingInvites(String userId, String email) async {
    await _supabase
        .from(SupabaseConstants.truckEmployeesTable)
        .update({
          'user_id': userId,
          'status': 'active',
          'linked_at': DateTime.now().toIso8601String(),
        })
        .eq('invited_email', email.trim().toLowerCase())
        .eq('status', 'pending')
        .withNetworkTimeout;
  }

  // Employee: fetch trucks they're assigned to
  Future<List<FoodTruck>> fetchEmployeeTrucks(String userId) async {
    final data = await _supabase
        .from(SupabaseConstants.truckEmployeesTable)
        .select('food_trucks(*, operating_hours(*), menu_items(*), menu_categories(*))')
        .eq('user_id', userId)
        .eq('status', 'active')
        .withNetworkTimeout;
    return (data as List)
        .map((e) => FoodTruck.fromMap(e['food_trucks'] as Map<String, dynamic>))
        .toList();
  }

  // ─── Shifts ────────────────────────────────────────────────────────────────

  // Employee: clock in — creates a new open shift
  Future<EmployeeShift> clockIn({
    required String employeeId,
    required String truckId,
    String? locationAddress,
  }) async {
    final data = await _supabase
        .from('employee_shifts')
        .insert({
          'employee_id': employeeId,
          'truck_id': truckId,
          'clocked_in_at': DateTime.now().toUtc().toIso8601String(),
          'location_address': locationAddress,
        })
        .select()
        .single()
        .withNetworkTimeout;
    return EmployeeShift.fromMap(data);
  }

  // Employee: clock out — closes the active shift
  Future<EmployeeShift> clockOut(String shiftId) async {
    final data = await _supabase
        .from('employee_shifts')
        .update({'clocked_out_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', shiftId)
        .select()
        .single()
        .withNetworkTimeout;
    return EmployeeShift.fromMap(data);
  }

  // Employee: fetch their own recent shifts for a truck (last 30)
  Future<List<EmployeeShift>> fetchMyShifts({
    required String employeeId,
    required String truckId,
  }) async {
    final data = await _supabase
        .from('employee_shifts')
        .select()
        .eq('employee_id', employeeId)
        .eq('truck_id', truckId)
        .order('clocked_in_at', ascending: false)
        .limit(30)
        .withNetworkTimeout;
    return (data as List)
        .map((e) => EmployeeShift.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // Employee: fetch their own shifts for a specific month
  Future<List<EmployeeShift>> fetchMyShiftsForMonth({
    required String employeeId,
    required String truckId,
    required int year,
    required int month,
  }) async {
    final first = DateTime.utc(year, month, 1);
    final next = DateTime.utc(year, month + 1, 1);
    final data = await _supabase
        .from('employee_shifts')
        .select()
        .eq('employee_id', employeeId)
        .eq('truck_id', truckId)
        .gte('clocked_in_at', first.toIso8601String())
        .lt('clocked_in_at', next.toIso8601String())
        .order('clocked_in_at', ascending: false)
        .withNetworkTimeout;
    return (data as List)
        .map((e) => EmployeeShift.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // Owner: fetch all worked shifts for their truck for a specific month
  Future<List<EmployeeShift>> fetchTruckShiftsForMonth({
    required String truckId,
    required int year,
    required int month,
  }) async {
    final first = DateTime.utc(year, month, 1);
    final next = DateTime.utc(year, month + 1, 1);
    final data = await _supabase
        .from('employee_shifts')
        .select('*, profiles(display_name)')
        .eq('truck_id', truckId)
        .gte('clocked_in_at', first.toIso8601String())
        .lt('clocked_in_at', next.toIso8601String())
        .order('clocked_in_at', ascending: false)
        .withNetworkTimeout;
    return (data as List)
        .map((e) => EmployeeShift.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // Owner: correct clock-in/out times on a worked shift
  Future<EmployeeShift> updateWorkedShift({
    required String shiftId,
    required DateTime clockedInAt,
    required DateTime clockedOutAt,
  }) async {
    final data = await _supabase
        .from('employee_shifts')
        .update({
          'clocked_in_at': clockedInAt.toUtc().toIso8601String(),
          'clocked_out_at': clockedOutAt.toUtc().toIso8601String(),
        })
        .eq('id', shiftId)
        .select()
        .single()
        .withNetworkTimeout;
    return EmployeeShift.fromMap(data);
  }

  // ─── Scheduled Shifts ──────────────────────────────────────────────────────

  // Owner: assign a scheduled shift to an employee
  Future<ScheduledShift> createScheduledShift({
    required String truckId,
    required String employeeId,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    String? notes,
    required String createdBy,
  }) async {
    final data = await _supabase
        .from('scheduled_shifts')
        .insert({
          'truck_id': truckId,
          'employee_id': employeeId,
          'scheduled_start': scheduledStart.toUtc().toIso8601String(),
          'scheduled_end': scheduledEnd.toUtc().toIso8601String(),
          'notes': notes,
          'created_by': createdBy,
        })
        .select()
        .single()
        .withNetworkTimeout;
    return ScheduledShift.fromMap(data);
  }

  // Employee: accept or decline a scheduled shift
  Future<ScheduledShift> respondToScheduledShift({
    required String shiftId,
    required String status, // 'accepted' | 'declined'
  }) async {
    final data = await _supabase
        .from('scheduled_shifts')
        .update({'status': status})
        .eq('id', shiftId)
        .select()
        .single()
        .withNetworkTimeout;
    return ScheduledShift.fromMap(data);
  }

  // Owner: delete a scheduled shift
  Future<void> deleteScheduledShift(String shiftId) async {
    await _supabase.from('scheduled_shifts').delete().eq('id', shiftId).withNetworkTimeout;
  }

  // Owner: all scheduled shifts for their truck in a month
  Future<List<ScheduledShift>> fetchScheduledShiftsForMonth({
    required String truckId,
    required int year,
    required int month,
  }) async {
    final first = DateTime.utc(year, month, 1);
    final next = DateTime.utc(year, month + 1, 1);
    final data = await _supabase
        .from('scheduled_shifts')
        .select('*, profiles:employee_id(display_name)')
        .eq('truck_id', truckId)
        .gte('scheduled_start', first.toIso8601String())
        .lt('scheduled_start', next.toIso8601String())
        .order('scheduled_start', ascending: true)
        .withNetworkTimeout;
    return (data as List)
        .map((e) => ScheduledShift.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // Employee: their scheduled shifts for a month
  Future<List<ScheduledShift>> fetchMyScheduledShiftsForMonth({
    required String employeeId,
    required String truckId,
    required int year,
    required int month,
  }) async {
    final first = DateTime.utc(year, month, 1);
    final next = DateTime.utc(year, month + 1, 1);
    final data = await _supabase
        .from('scheduled_shifts')
        .select()
        .eq('employee_id', employeeId)
        .eq('truck_id', truckId)
        .gte('scheduled_start', first.toIso8601String())
        .lt('scheduled_start', next.toIso8601String())
        .order('scheduled_start', ascending: true)
        .withNetworkTimeout;
    return (data as List)
        .map((e) => ScheduledShift.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // Owner: fetch recent shifts for their truck (last 50, includes employee name)
  // Kept for backwards compat — prefer fetchTruckShiftsForMonth for calendar.
  Future<List<EmployeeShift>> fetchTruckShifts(String truckId) async {
    final data = await _supabase
        .from('employee_shifts')
        .select('*, profiles(display_name)')
        .eq('truck_id', truckId)
        .order('clocked_in_at', ascending: false)
        .limit(50)
        .withNetworkTimeout;
    return (data as List)
        .map((e) => EmployeeShift.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}

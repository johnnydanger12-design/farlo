import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../features/map/models/food_truck.dart';
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
        .order('invited_at');
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
    });
    return (result as Map<String, dynamic>)['already_user'] as bool;
  }

  // Owner: remove employee
  Future<void> removeEmployee(String employeeId) async {
    await _supabase
        .from(SupabaseConstants.truckEmployeesTable)
        .update({'status': 'removed'})
        .eq('id', employeeId);
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
        .eq('status', 'pending');
  }

  // Employee: fetch trucks they're assigned to
  Future<List<FoodTruck>> fetchEmployeeTrucks(String userId) async {
    final data = await _supabase
        .from(SupabaseConstants.truckEmployeesTable)
        .select('food_trucks(*, operating_hours(*), menu_items(*))')
        .eq('user_id', userId)
        .eq('status', 'active');
    return (data as List)
        .map((e) => FoodTruck.fromMap(e['food_trucks'] as Map<String, dynamic>))
        .toList();
  }
}

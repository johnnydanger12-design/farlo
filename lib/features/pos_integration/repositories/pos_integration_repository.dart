import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/extensions/future_timeout.dart';
import '../models/pos_integration.dart';

class CloverTestResult {
  const CloverTestResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class PosIntegrationRepository {
  PosIntegrationRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<PosIntegration?> fetchForTruck(String truckId) async {
    final row = await _supabase
        .from('pos_integrations')
        .select('provider, external_merchant_id, environment, enabled, clover_order_type_id, clover_employee_id, square_location_id')
        .eq('truck_id', truckId)
        .eq('enabled', true)
        .maybeSingle()
        .withNetworkTimeout;
    if (row == null) return null;
    return PosIntegration.fromMap(row);
  }

  Future<CloverTestResult> testCloverConnection({
    required String merchantId,
    required String apiToken,
    required String environment,
  }) async {
    final res = await _supabase.functions.invoke('test-clover-connection', body: {
      'merchant_id': merchantId,
      'api_token': apiToken,
      'environment': environment,
    }).withNetworkTimeout;
    final data = res.data as Map<String, dynamic>;
    return CloverTestResult(ok: data['ok'] as bool, message: data['message'] as String?);
  }

  /// Re-validates credentials live server-side regardless of any prior
  /// Test Connection result the client reports — throws with a user-facing
  /// message on any failure (invalid credentials, not a truck owner, save error).
  Future<void> connectClover({
    required String merchantId,
    required String apiToken,
    required String environment,
    String? orderTypeId,
  }) async {
    final res = await _supabase.functions.invoke('connect-clover', body: {
      'merchant_id': merchantId,
      'api_token': apiToken,
      'environment': environment,
      if (orderTypeId != null && orderTypeId.isNotEmpty) 'order_type_id': orderTypeId,
    }).withNetworkTimeout;
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception(data['message'] as String? ?? data['error'] as String);
    }
  }

  Future<void> setEnabled(String truckId, bool enabled) async {
    await _supabase
        .from('pos_integrations')
        .update({'enabled': enabled})
        .eq('truck_id', truckId)
        .withNetworkTimeout;
  }

  Future<void> submitPosRequest(String truckId, {required String requestedProvider, String? note}) async {
    await _supabase.from('pos_requests').insert({
      'truck_id': truckId,
      'requested_provider': requestedProvider,
      'note': note,
    }).withNetworkTimeout;
  }

  /// Returns Square's OAuth authorize URL to launch in an external browser —
  /// mirrors OrdersRepository.connectStripeAccount's shape.
  Future<String> startSquareOauth({required String environment}) async {
    final res = await _supabase.functions.invoke('square-oauth-start', body: {
      'environment': environment,
    }).withNetworkTimeout;
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error'] as String);
    return data['url'] as String;
  }

  /// Called with no location chosen yet — fetches the live list left pending
  /// by square-oauth-callback when a merchant has more than one location.
  Future<List<({String id, String name})>> fetchSquareLocations() async {
    final res = await _supabase.functions.invoke('square-select-location', body: const {}).withNetworkTimeout;
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error'] as String);
    final locations = (data['locations'] as List).cast<Map<String, dynamic>>();
    return locations.map((l) => (id: l['id'] as String, name: l['name'] as String)).toList();
  }

  Future<void> selectSquareLocation(String locationId) async {
    final res = await _supabase.functions.invoke('square-select-location', body: {
      'location_id': locationId,
    }).withNetworkTimeout;
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error'] as String);
  }
}

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/extensions/future_timeout.dart';
import '../models/data_export_request.dart';

/// Thrown when the user already has a pending/processing export request —
/// surfaced by both request-data-export's pre-check and, if a request
/// slips past that check, the DB's own partial unique index.
class DataExportAlreadyInProgressException implements Exception {}

class DataExportRepository {
  DataExportRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<DataExportRequest?> fetchLatestRequest(String userId) async {
    final row = await _supabase
        .from('data_export_requests')
        .select()
        .eq('user_id', userId)
        .order('requested_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .withNetworkTimeout;
    if (row == null) return null;
    return DataExportRequest.fromMap(row);
  }

  Future<void> requestExport() async {
    final res = await _supabase.functions.invoke('request-data-export').withNetworkTimeout;
    final data = res.data as Map<String, dynamic>?;
    if (data != null && data['error'] == 'export_already_in_progress') {
      throw DataExportAlreadyInProgressException();
    }
    if (data != null && data['error'] != null) {
      throw Exception(data['error']);
    }
  }

  Stream<DataExportRequest?> streamLatestRequest(String userId) {
    StreamController<DataExportRequest?>? controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final latest = await fetchLatestRequest(userId);
        final c = controller;
        if (c != null && !c.isClosed) c.add(latest);
      } catch (_) {}
    }

    controller = StreamController<DataExportRequest?>(
      onListen: () {
        refresh();
        channel = _supabase
            .channel('data-export-requests-$userId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'data_export_requests',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () {
        channel?.unsubscribe();
        channel = null;
        controller?.close();
      },
    );

    return controller.stream;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/data_export_request.dart';
import '../repositories/data_export_repository.dart';

final dataExportRepositoryProvider = Provider<DataExportRepository>((ref) {
  return DataExportRepository(Supabase.instance.client);
});

final latestDataExportRequestProvider =
    StreamProvider.autoDispose<DataExportRequest?>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return Stream.value(null);
  return ref.watch(dataExportRepositoryProvider).streamLatestRequest(userId);
});

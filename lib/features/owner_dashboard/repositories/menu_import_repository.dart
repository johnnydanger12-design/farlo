import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../services/storage_service.dart';
import '../models/parsed_menu_item.dart';

// A Claude vision/document parse can take 10-40+ seconds depending on file
// size/page count — much longer than the app's usual 15s network timeout,
// which is tuned for quick CRUD calls, not this.
const _menuParseTimeout = Duration(seconds: 90);

class MenuImportRepository {
  MenuImportRepository(this._supabase);
  final SupabaseClient _supabase;

  /// Uploads [file] (a photo or PDF of a paper menu) to the truck-menus
  /// bucket and returns its storage path (not the public URL — the parse
  /// call needs the path to download the file server-side).
  Future<String> _uploadAndGetPath(String truckId, File file) async {
    final url = await storageServiceInstance.uploadImage(
      SupabaseConstants.truckMenusBucket,
      file,
      ownerId: truckId,
    );
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf(SupabaseConstants.truckMenusBucket);
    if (bucketIndex == -1 || bucketIndex + 1 >= segments.length) {
      throw Exception('Could not determine upload path');
    }
    return segments.sublist(bucketIndex + 1).join('/');
  }

  /// Uploads the menu file and asks Claude to parse it into structured items.
  /// Never writes to menu_items/menu_categories — the caller reviews the
  /// result and calls FoodTruckRepository.bulkAddMenuItems to commit it.
  Future<List<ParsedMenuItem>> uploadAndParse(String truckId, File file) async {
    final storagePath = await _uploadAndGetPath(truckId, file);
    try {
      final res = await _supabase.functions.invoke(
        'parse-menu-upload',
        body: {'truck_id': truckId, 'storage_path': storagePath},
      ).timeout(
        _menuParseTimeout,
        onTimeout: () => throw TimeoutException('Menu parse timed out. Check your connection and try again.'),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['error'] != null) throw Exception(data['error']);
      final items = (data['items'] as List? ?? [])
          .map((e) => ParsedMenuItem.fromMap(e as Map<String, dynamic>))
          .toList();
      return items;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String ? details['error'] as String : null;
      throw Exception(message ?? 'Could not parse menu.');
    } finally {
      // Best-effort cleanup — the raw upload isn't needed once parsing is
      // done (or has failed); don't let a delete failure mask the real result.
      try {
        await storageServiceInstance.deleteByUrl(
          SupabaseConstants.truckMenusBucket,
          _supabase.storage.from(SupabaseConstants.truckMenusBucket).getPublicUrl(storagePath),
        );
      } catch (_) {}
    }
  }
}

final menuImportRepositoryProvider = Provider<MenuImportRepository>((ref) {
  return MenuImportRepository(Supabase.instance.client);
});

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService(this._supabase);

  final SupabaseClient _supabase;

  /// Uploads [file] to [bucket] under a unique path keyed by [ownerId].
  /// Returns the public URL of the uploaded object.
  Future<String> uploadImage(String bucket, File file, {required String ownerId}) async {
    final ext = file.path.split('.').last.toLowerCase();
    final path = '$ownerId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supabase.storage.from(bucket).upload(path, file, fileOptions: const FileOptions(upsert: true));
    return _supabase.storage.from(bucket).getPublicUrl(path);
  }

  /// Deletes an object from [bucket] given its full public [url].
  Future<void> deleteByUrl(String bucket, String url) async {
    final uri = Uri.parse(url);
    // Public URLs look like: .../storage/v1/object/public/<bucket>/<path>
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf(bucket);
    if (bucketIndex == -1 || bucketIndex + 1 >= segments.length) return;
    final path = segments.sublist(bucketIndex + 1).join('/');
    await _supabase.storage.from(bucket).remove([path]);
  }
}

final storageServiceInstance = StorageService(Supabase.instance.client);

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

// ARCH-5 (code-quality.md, image pipeline): caps the pixel dimensions an
// ImagePicker call will hand back, applied consistently across every
// non-avatar image upload (truck logo, truck photo, menu item photo — the
// avatar upload already had its own 512x512 cap). Generous enough for a
// full-bleed carousel display on a retina phone; final on-screen serving
// size (thumbnail vs. full) is handled by [transformedImageUrl] at render
// time instead of maintaining multiple upload-time resolutions.
const uploadImageMaxDimension = 1600.0;

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

/// Requests a resized rendition of an already-uploaded Supabase Storage
/// public image [url] via Storage's on-the-fly image-transformation API
/// (`/render/image/public/...` instead of `/object/public/...`), so
/// thumbnail-sized UI (map pins, list rows, grid cards) doesn't download —
/// and [CachedNetworkImage] doesn't cache to disk — the full-resolution
/// original every time (ARCH-5, code-quality.md).
///
/// Falls back to the original [url] unchanged for any URL that isn't a
/// recognizable Supabase Storage object URL (e.g. already-transformed URLs,
/// or a non-Storage URL), so callers can apply this unconditionally.
String transformedImageUrl(String url, {int? width, int? height, int quality = 75}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final objectIndex = uri.pathSegments.indexOf('object');
  if (objectIndex == -1) return url;

  final renderedSegments = [
    ...uri.pathSegments.sublist(0, objectIndex),
    'render',
    'image',
    ...uri.pathSegments.sublist(objectIndex + 1),
  ];
  return uri.replace(
    pathSegments: renderedSegments,
    queryParameters: {
      if (width != null) 'width': '$width',
      if (height != null) 'height': '$height',
      'quality': '$quality',
    },
  ).toString();
}

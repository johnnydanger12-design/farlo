import 'package:flutter_test/flutter_test.dart';
import 'package:farlo/services/storage_service.dart';

void main() {
  group('transformedImageUrl', () {
    // ARCH-5 (code-quality.md, image pipeline): confirms the raw
    // /object/public/ Storage URL is rewritten to Storage's on-the-fly
    // image-transformation endpoint (/render/image/public/) with the
    // requested width/height/quality query params — verified live against
    // the real project in this iteration's Green step (a 1.94MB original
    // came back as a 4KB resize), this test locks the URL-shaping logic in
    // as a permanent regression test.
    test('rewrites /object/public/ to /render/image/public/ and adds width/height/quality', () {
      const url = 'https://weflrxyerxpsafcdetya.supabase.co/storage/v1/object/public/truck-logos/abc/123.jpg';

      final result = transformedImageUrl(url, width: 100, height: 200);

      final uri = Uri.parse(result);
      expect(uri.path, '/storage/v1/render/image/public/truck-logos/abc/123.jpg');
      expect(uri.queryParameters['width'], '100');
      expect(uri.queryParameters['height'], '200');
      expect(uri.queryParameters['quality'], '75');
    });

    test('defaults quality to 75 and omits width/height when not provided', () {
      const url = 'https://weflrxyerxpsafcdetya.supabase.co/storage/v1/object/public/truck-photos/x/y.jpg';

      final result = transformedImageUrl(url);

      final uri = Uri.parse(result);
      expect(uri.queryParameters.containsKey('width'), isFalse);
      expect(uri.queryParameters.containsKey('height'), isFalse);
      expect(uri.queryParameters['quality'], '75');
    });

    test('respects an explicit quality override', () {
      const url = 'https://weflrxyerxpsafcdetya.supabase.co/storage/v1/object/public/avatars/u1.jpg';

      final result = transformedImageUrl(url, width: 50, quality: 90);

      expect(Uri.parse(result).queryParameters['quality'], '90');
    });

    test('leaves a non-Storage-object URL unchanged rather than corrupting it', () {
      const url = 'https://example.com/some/other/path.jpg';

      expect(transformedImageUrl(url, width: 100), url);
    });

    test('leaves an unparseable URL unchanged', () {
      const notAUrl = 'not a url at all';

      expect(transformedImageUrl(notAUrl, width: 100), notAUrl);
    });
  });
}

// Port of lib/services/storage_service.dart's transformedImageUrl() so
// photos are served through Supabase Storage's on-the-fly image transform
// endpoint instead of full-size. Swaps /object/public/... for
// /render/image/public/... and appends width/height/quality params.
export function transformedImageUrl(
  url: string,
  { width, height, quality = 75 }: { width?: number; height?: number; quality?: number } = {},
): string {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return url;
  }

  const segments = parsed.pathname.split('/').filter(Boolean);
  const objectIndex = segments.indexOf('object');
  if (objectIndex === -1) return url;

  const renderedSegments = [
    ...segments.slice(0, objectIndex),
    'render',
    'image',
    ...segments.slice(objectIndex + 1),
  ];

  parsed.pathname = '/' + renderedSegments.join('/');
  if (width != null) parsed.searchParams.set('width', String(width));
  if (height != null) parsed.searchParams.set('height', String(height));
  parsed.searchParams.set('quality', String(quality));

  return parsed.toString();
}

import { transformedImageUrl } from '../lib/imageUrl';

export function Hero({ photoUrls, logoUrl, name }: { photoUrls: string[]; logoUrl: string | null; name: string }) {
  const heroImage = photoUrls[0] ?? logoUrl;
  const thumbnails = photoUrls.length > 1 ? photoUrls.slice(1) : [];

  return (
    <div>
      <div className="h-56 w-full overflow-hidden bg-[var(--border)] sm:h-72">
        {heroImage ? (
          <img
            src={transformedImageUrl(heroImage, { width: 1200, height: 600 })}
            alt={name}
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-[var(--primary)] text-5xl font-semibold text-white">
            {name.charAt(0).toUpperCase()}
          </div>
        )}
      </div>
      {thumbnails.length > 0 && (
        <div className="flex gap-2 overflow-x-auto px-4 py-3">
          {thumbnails.map((url) => (
            <img
              key={url}
              src={transformedImageUrl(url, { width: 200, height: 200 })}
              alt={name}
              className="h-16 w-16 flex-shrink-0 rounded-lg object-cover"
            />
          ))}
        </div>
      )}
    </div>
  );
}

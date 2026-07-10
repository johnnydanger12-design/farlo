import { DownloadCta } from './DownloadCta';

// Shown both for a genuinely unknown slug and for a real business that
// simply hasn't been activated on Farlo yet -- the query can't tell the
// difference (RLS filters is_active = true either way), and it shouldn't:
// a business isn't discoverable until the owner is ready, full stop.
export function NotFound() {
  return (
    <div className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-4 px-6 text-center">
      <div className="text-4xl">🍴</div>
      <h1 className="text-xl font-semibold text-[var(--text)]">
        This business isn't live on Farlo yet
      </h1>
      <p className="text-sm text-[var(--muted)]">
        Check back soon, or download Farlo to discover other local businesses near you.
      </p>
      <div className="mt-2">
        <DownloadCta />
      </div>
    </div>
  );
}

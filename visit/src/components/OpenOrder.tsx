import { useEffect } from 'react';
import { DownloadCta } from './DownloadCta';

// The handoff page a "View Your Order" receipt-email button lands on —
// mirrors the two-step pattern used by most order-confirmation emails
// (open a plain webpage first, which then opens the native app to the
// specific order): no order data is fetched or shown here at all. The
// orders table's RLS already scopes reads to the consumer/owner/employee,
// so an anon-key public page couldn't display real order details even if
// it tried -- this page's only job is handing off to the app, which does
// the real, authenticated fetch itself (see OrderLookupScreen in the app).
export function OpenOrder({ orderId }: { orderId: string }) {
  const appLink = `farlo://order/${encodeURIComponent(orderId)}`;

  // Best-effort auto-attempt on load — many mobile browsers (especially an
  // email client's built-in in-app browser) block a synchronous custom-scheme
  // redirect with no user gesture, so this silently no-ops there and the
  // visible button below is the real, reliable path either way.
  useEffect(() => {
    window.location.href = appLink;
  }, [appLink]);

  return (
    <div className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-4 px-6 text-center">
      <div className="text-4xl">🧾</div>
      <h1 className="text-xl font-semibold text-[var(--text)]">Opening your order…</h1>
      <p className="text-sm text-[var(--muted)]">
        If the Farlo app doesn't open automatically, tap below.
      </p>
      <a
        href={appLink}
        className="rounded-lg bg-[var(--primary)] px-6 py-3 text-sm font-medium text-white transition hover:opacity-90"
      >
        Open in Farlo App
      </a>
      <div className="mt-4">
        <p className="mb-3 text-sm text-[var(--muted)]">Don't have the app yet?</p>
        <DownloadCta />
      </div>
    </div>
  );
}

// Cloudflare Pages Function — runs for every request to visit.farlo.app,
// ahead of the static React app. Social-media link-preview crawlers
// (Facebook, Twitter/X, iMessage, Slack, etc.) never execute JavaScript,
// so the client-side App.tsx fetching the business's data is invisible to
// them — the og:image/og:title/og:description tags have to already be
// correct in the raw HTML by the time the crawler reads it. This rewrites
// those tags (already present as defaults in index.html) with the specific
// business's own logo/photo before returning the page, falling back to the
// static Farlo-logo defaults untouched for the bare domain or an unknown slug.

const SUPABASE_URL = 'https://weflrxyerxpsafcdetya.supabase.co';
// Publishable anon key — safe to embed, same one the client bundle itself ships with.
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndlZmxyeHllcnhwc2FmY2RldHlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyMjU0MDksImV4cCI6MjA5NjgwMTQwOX0.QVUUqVmoGEjzaRBiBJeYouLpQ3_1cqsB0e8qUuyhxtc';

interface TruckPreview {
  name: string;
  description: string | null;
  cuisine_type: string;
  logo_url: string | null;
  photo_urls: string[] | null;
}

function escapeAttr(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
}

export const onRequest: PagesFunction = async (context) => {
  const response = await context.next();

  const url = new URL(context.request.url);
  const slug = url.pathname.replace(/^\/+|\/+$/g, '').toLowerCase();
  if (!slug) return response;

  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/food_trucks?slug=eq.${encodeURIComponent(slug)}&is_active=eq.true&select=name,description,cuisine_type,logo_url,photo_urls`,
      { headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}` } },
    );
    if (!res.ok) return response;

    const rows = (await res.json()) as TruckPreview[];
    const truck = rows[0];
    if (!truck) return response;

    const image = truck.logo_url || truck.photo_urls?.[0] || 'https://visit.farlo.app/farlo-logo.png';
    const title = escapeAttr(`${truck.name} on Farlo`);
    const description = escapeAttr(
      truck.description?.trim() || `Order ahead from ${truck.name} — ${truck.cuisine_type} on Farlo.`,
    );
    const pageUrl = escapeAttr(url.toString());

    const escapedImage = escapeAttr(image);
    return new HTMLRewriter()
      .on('title', { element: (el) => { el.setInnerContent(`${truck.name} on Farlo`); } })
      .on('meta[property="og:title"]', { element: (el) => { el.setAttribute('content', title); } })
      .on('meta[property="og:description"]', { element: (el) => { el.setAttribute('content', description); } })
      .on('meta[property="og:image"]', { element: (el) => { el.setAttribute('content', escapedImage); } })
      .on('meta[property="og:url"]', { element: (el) => { el.setAttribute('content', pageUrl); } })
      .on('meta[name="twitter:title"]', { element: (el) => { el.setAttribute('content', title); } })
      .on('meta[name="twitter:description"]', { element: (el) => { el.setAttribute('content', description); } })
      .on('meta[name="twitter:image"]', { element: (el) => { el.setAttribute('content', escapedImage); } })
      .transform(response);
  } catch {
    // Any failure here (network blip, unexpected shape) must never break
    // the actual page load — just serve the untouched default response.
    return response;
  }
};

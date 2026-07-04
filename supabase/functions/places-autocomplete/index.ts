// Proxies Google Places Autocomplete/Details so GOOGLE_PLACES_API_KEY never ships in
// the Flutter client. The key was previously compiled directly into the app via
// --dart-define, extractable via `strings` on the built APK/IPA and usable for
// unlimited, uncapped billing abuse independent of anything Farlo could add
// server-side later (Phase 7 security audit, Critical Finding N1). This endpoint is
// intentionally unauthenticated (verify_jwt: false) because PlacesAutocompleteField is
// used from the pre-signup owner registration screen, before a session exists — the
// fix here is removing the extractable, reusable-outside-Farlo credential, not adding
// auth this specific call site can't provide. Only the two actions the client actually
// needs are exposed, nothing else on the Places API surface.
const PLACES_API_KEY = Deno.env.get('GOOGLE_PLACES_API_KEY')!;

Deno.serve(async (req: Request) => {
  if (req.method !== 'GET') return new Response('Method not allowed', { status: 405 });
  if (!PLACES_API_KEY) {
    return new Response(JSON.stringify({ error: 'GOOGLE_PLACES_API_KEY not set' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get('action');

  if (action === 'autocomplete') {
    const input = (url.searchParams.get('input') ?? '').slice(0, 200);
    if (!input) {
      return new Response(JSON.stringify({ error: 'input is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    const upstream = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
    upstream.searchParams.set('input', input);
    upstream.searchParams.set('components', 'country:us');
    upstream.searchParams.set('key', PLACES_API_KEY);
    const res = await fetch(upstream);
    const data = await res.json();
    return new Response(JSON.stringify(data), {
      status: res.status,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (action === 'details') {
    const placeId = (url.searchParams.get('place_id') ?? '').slice(0, 200);
    if (!placeId) {
      return new Response(JSON.stringify({ error: 'place_id is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    const upstream = new URL('https://maps.googleapis.com/maps/api/place/details/json');
    upstream.searchParams.set('place_id', placeId);
    upstream.searchParams.set('fields', 'formatted_address,geometry');
    upstream.searchParams.set('key', PLACES_API_KEY);
    const res = await fetch(upstream);
    const data = await res.json();
    return new Response(JSON.stringify(data), {
      status: res.status,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ error: 'action must be "autocomplete" or "details"' }), {
    status: 400,
    headers: { 'Content-Type': 'application/json' },
  });
});

// Every other Edge Function in this codebase is called from Flutter or cron — neither
// does a CORS preflight, so this never came up before aiden-chat, the first function
// called directly from a real browser (the founder dashboard). An explicit allowlist
// rather than '*' — this function is Bearer-token authenticated (not cookie-based), so
// a wildcard origin wouldn't actually let another site forge a request without already
// having the founder's real access token, but an allowlist is still the safer default.
const ALLOWED_ORIGINS = new Set(['https://dash.farlo.app', 'http://localhost:5173']);

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? '';
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'https://dash.farlo.app',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

// Call first in every handler — returns a response for the browser's preflight OPTIONS
// request, or null if this isn't one (continue with normal handling).
export function handlePreflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(req) });
  }
  return null;
}

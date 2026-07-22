// Shared by square-oauth-start/square-oauth-callback. Square's redirect back
// to square-oauth-callback is a plain browser GET with no Supabase JWT
// available (same reason stripe-connect-onboard's return/refresh URLs are
// plain HTTPS, not a custom scheme) — `state` is how the callback recovers
// which truck initiated the flow, HMAC-signed so it can't be forged/tampered
// with, and timestamped so a stale/replayed state is rejected.
const STATE_MAX_AGE_MS = 10 * 60 * 1000;

function base64url(bytes: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

async function hmac(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return base64url(sig);
}

export async function signState(secret: string, truckId: string, environment: string): Promise<string> {
  const payload = `${truckId}.${environment}.${Date.now()}`;
  const sig = await hmac(secret, payload);
  return `${payload}.${sig}`;
}

export async function verifyState(
  secret: string,
  state: string,
): Promise<{ truckId: string; environment: string } | null> {
  const parts = state.split('.');
  if (parts.length !== 4) return null;
  const [truckId, environment, tsStr, sig] = parts;
  const payload = `${truckId}.${environment}.${tsStr}`;
  const expectedSig = await hmac(secret, payload);
  if (expectedSig !== sig) return null;
  const ts = Number(tsStr);
  if (!Number.isFinite(ts) || Date.now() - ts > STATE_MAX_AGE_MS) return null;
  return { truckId, environment };
}

export function squareApiBaseUrl(environment: string): string {
  return environment === 'sandbox' ? 'https://connect.squareupsandbox.com' : 'https://connect.squareup.com';
}

// Square issues a SEPARATE Application ID/Secret pair per environment for the
// same app (confirmed via Square's own docs) — the production pair is
// rejected outright by the sandbox authorize/token endpoints and vice versa.
// Real bug found live: picking "Sandbox" in the Connect Square screen sent
// the production Application ID to connect.squareupsandbox.com, which
// doesn't recognize it, so the authorize page failed to load.
export function getSquareAppCredentials(
  environment: string,
): { applicationId: string; applicationSecret: string } | null {
  const applicationId = environment === 'sandbox'
    ? Deno.env.get('SQUARE_SANDBOX_APPLICATION_ID')
    : Deno.env.get('SQUARE_APPLICATION_ID');
  const applicationSecret = environment === 'sandbox'
    ? Deno.env.get('SQUARE_SANDBOX_APPLICATION_SECRET')
    : Deno.env.get('SQUARE_APPLICATION_SECRET');
  if (!applicationId || !applicationSecret) return null;
  return { applicationId, applicationSecret };
}

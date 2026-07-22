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

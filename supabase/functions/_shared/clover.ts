// Shared between test-clover-connection (client-facing "Test Connection"
// button) and connect-clover (which never trusts a client-reported
// "already tested" flag and re-validates live before saving).
export function cloverBaseUrl(environment: string): string {
  return environment === 'sandbox' ? 'https://apisandbox.dev.clover.com' : 'https://api.clover.com';
}

export type CloverTestResult =
  | { ok: true }
  | { ok: false; reason: 'invalid_token' | 'invalid_merchant_id' | 'network_error' | 'unknown'; message: string };

// Hits the same GET /v3/merchants/{id}/orders endpoint the real order push
// path uses, so a pass here genuinely proves the token/scope combo that matters.
export async function testCloverConnection(
  merchantId: string,
  apiToken: string,
  environment: string,
): Promise<CloverTestResult> {
  try {
    const res = await fetch(
      `${cloverBaseUrl(environment)}/v3/merchants/${encodeURIComponent(merchantId)}/orders?limit=1`,
      { headers: { Authorization: `Bearer ${apiToken}` } },
    );
    if (res.ok) return { ok: true };
    if (res.status === 401 || res.status === 403) {
      return {
        ok: false,
        reason: 'invalid_token',
        message: 'Clover rejected this API token. Double-check you selected Orders, Print, Payments, and Customers when generating it in your Clover dashboard — a token missing any of those scopes will fail here.',
      };
    }
    if (res.status === 404) {
      return {
        ok: false,
        reason: 'invalid_merchant_id',
        message: "Merchant ID not found. Get it from your Clover dashboard's URL (the string after /merchant/), not from a receipt, statement, or invoice.",
      };
    }
    return { ok: false, reason: 'unknown', message: `Clover returned an unexpected error (${res.status}). Please try again.` };
  } catch (err) {
    console.error('testCloverConnection network error:', err);
    return { ok: false, reason: 'network_error', message: 'Could not reach Clover. Check your connection and try again.' };
  }
}

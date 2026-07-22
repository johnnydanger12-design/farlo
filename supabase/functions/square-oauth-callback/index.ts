// Square's redirect target after a merchant approves (or denies) the OAuth
// request — a plain browser GET, so this is public (--no-verify-jwt) and
// recovers the initiating truck from the signed `state` param rather than a
// Supabase JWT. Exchanges the code for tokens, stores them in Vault, and
// either finalizes the connection (single location) or leaves it pending
// (multiple locations, finished by square-select-location) before redirecting
// back into the app via the farlo:// custom scheme — mirrors
// stripe_connect_screen.dart's deep-link-listen + lifecycle-resume pattern.
//
// UNVERIFIED end-to-end: no real Square Application exists yet. Blocked on
// Johnny creating one and setting SQUARE_APPLICATION_ID +
// SQUARE_APPLICATION_SECRET + SQUARE_OAUTH_STATE_SECRET as this function's secrets.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { squareApiBaseUrl, verifyState } from '../_shared/squareOauth.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function redirect(status: string, message?: string): Response {
  const params = new URLSearchParams({ status, ...(message ? { message } : {}) });
  return new Response(null, {
    status: 302,
    headers: { Location: `farlo://square-connect?${params.toString()}` },
  });
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  const squareError = url.searchParams.get('error');

  if (squareError) {
    return redirect('error', 'Square authorization was cancelled or denied.');
  }
  if (!code || !state) {
    return redirect('error', 'Missing authorization code.');
  }

  const stateSecret = Deno.env.get('SQUARE_OAUTH_STATE_SECRET');
  if (!stateSecret) return redirect('error', 'Square is not yet configured.');

  const verified = await verifyState(stateSecret, state);
  if (!verified) return redirect('error', 'This authorization link expired or is invalid. Please try again.');
  const { truckId, environment } = verified;

  const applicationId = Deno.env.get('SQUARE_APPLICATION_ID');
  const applicationSecret = Deno.env.get('SQUARE_APPLICATION_SECRET');
  if (!applicationId || !applicationSecret) return redirect('error', 'Square is not yet configured.');

  try {
    const callbackUrl = `${Deno.env.get('SUPABASE_URL')!}/functions/v1/square-oauth-callback`;
    const tokenRes = await fetch(`${squareApiBaseUrl(environment)}/oauth2/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: applicationId,
        client_secret: applicationSecret,
        code,
        grant_type: 'authorization_code',
        redirect_uri: callbackUrl,
      }),
    });
    if (!tokenRes.ok) {
      console.error(`Square token exchange failed (${tokenRes.status}): ${await tokenRes.text()}`);
      return redirect('error', 'Could not complete Square authorization.');
    }
    const token = await tokenRes.json();
    const merchantId = token.merchant_id as string;
    const accessToken = token.access_token as string;
    const refreshToken = token.refresh_token as string;
    const expiresAt = token.expires_at as string;

    const locationsRes = await fetch(`${squareApiBaseUrl(environment)}/v2/locations`, {
      headers: { Authorization: `Bearer ${accessToken}`, 'Square-Version': '2025-01-23' },
    });
    const locationsBody = locationsRes.ok ? await locationsRes.json() : { locations: [] };
    const locations = (locationsBody.locations ?? []) as { id: string }[];

    const accessSecretName = `square_access_token_${truckId}_${Date.now()}`;
    const refreshSecretName = `square_refresh_token_${truckId}_${Date.now()}`;
    await supabase.rpc('create_pos_secret', { p_secret: accessToken, p_name: accessSecretName });
    await supabase.rpc('create_pos_secret', { p_secret: refreshToken, p_name: refreshSecretName });

    // Only one enabled POS integration per truck — disable any other
    // provider's row before this one is (potentially) enabled.
    await supabase.from('pos_integrations').update({ enabled: false }).eq('truck_id', truckId);

    const singleLocation = locations.length === 1;
    const { error: upsertError } = await supabase.from('pos_integrations').upsert(
      {
        truck_id: truckId,
        provider: 'square',
        external_merchant_id: merchantId,
        api_token_secret_name: accessSecretName,
        refresh_token_secret_name: refreshSecretName,
        token_expires_at: expiresAt,
        square_location_id: singleLocation ? locations[0].id : null,
        environment,
        enabled: singleLocation,
      },
      { onConflict: 'truck_id,provider' },
    );
    if (upsertError) {
      console.error('pos_integrations upsert failed:', upsertError);
      return redirect('error', 'Could not save your Square connection.');
    }

    return redirect(singleLocation ? 'success' : 'needs_location');
  } catch (err) {
    console.error('square-oauth-callback failed:', err);
    return redirect('error', 'Something went wrong connecting Square.');
  }
});

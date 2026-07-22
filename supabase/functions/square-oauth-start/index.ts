// Called from the self-serve Connect Square screen — resolves the caller's
// own truck, builds a signed state binding truck id + environment, and
// returns Square's real OAuth authorize URL for the app to launch in an
// external browser (same launchUrl(..., mode: externalApplication) pattern
// stripe_connect_screen.dart already uses for Stripe Connect).
//
// UNVERIFIED end-to-end: no real Square Application exists yet. Blocked on
// Johnny creating one in Square's Developer Dashboard (free, instant, no
// approval wait for a private/unlisted integration) and setting
// SQUARE_APPLICATION_ID + SQUARE_APPLICATION_SECRET + SQUARE_OAUTH_STATE_SECRET
// as this function's secrets.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { signState, squareApiBaseUrl } from '../_shared/squareOauth.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Minimal scope set for order push + fulfillment: read the merchant profile
// (to confirm which merchant authorized) and read/write orders.
const SQUARE_SCOPES = ['MERCHANT_PROFILE_READ', 'ORDERS_WRITE', 'ORDERS_READ'].join('+');

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response('Unauthorized', { status: 401 });

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return new Response('Unauthorized', { status: 401 });

  const applicationId = Deno.env.get('SQUARE_APPLICATION_ID');
  const stateSecret = Deno.env.get('SQUARE_OAUTH_STATE_SECRET');
  if (!applicationId || !stateSecret) {
    return new Response(
      JSON.stringify({ error: 'Square is not yet configured. Contact support.' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  let body: { environment?: string };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const environment = body.environment === 'sandbox' ? 'sandbox' : 'production';

  const { data: truck, error: truckError } = await supabase
    .from('food_trucks')
    .select('id')
    .eq('owner_id', user.id)
    .single();
  if (truckError || !truck) {
    return new Response(JSON.stringify({ error: 'not_a_truck_owner' }), { status: 403 });
  }

  const state = await signState(stateSecret, truck.id, environment);
  const callbackUrl = `${Deno.env.get('SUPABASE_URL')!}/functions/v1/square-oauth-callback`;
  const authorizeUrl =
    `${squareApiBaseUrl(environment)}/oauth2/authorize` +
    `?client_id=${encodeURIComponent(applicationId)}` +
    `&scope=${SQUARE_SCOPES}` +
    `&session=false` +
    `&state=${encodeURIComponent(state)}` +
    `&redirect_uri=${encodeURIComponent(callbackUrl)}`;

  return new Response(JSON.stringify({ url: authorizeUrl }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});

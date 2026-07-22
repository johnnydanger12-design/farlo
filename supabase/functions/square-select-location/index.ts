// Finishes a Square connection left pending by square-oauth-callback because
// the merchant has more than one location. Called with no body to fetch the
// live location list (re-fetched fresh rather than trusting anything cached),
// then again with a location_id to finalize — mirrors connect-clover's
// "re-validate live before saving" discipline.
//
// UNVERIFIED end-to-end: no real Square Application exists yet.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { squareApiBaseUrl } from '../_shared/squareOauth.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

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

  const { data: truck, error: truckError } = await supabase
    .from('food_trucks')
    .select('id')
    .eq('owner_id', user.id)
    .single();
  if (truckError || !truck) {
    return new Response(JSON.stringify({ error: 'not_a_truck_owner' }), { status: 403 });
  }

  // Pending row lookup deliberately does NOT filter on enabled — this row is
  // enabled: false until a location is picked, unlike get_pos_credentials
  // (which only ever resolves the one currently-enabled integration).
  const { data: pending } = await supabase
    .from('pos_integrations')
    .select('environment')
    .eq('truck_id', truck.id)
    .eq('provider', 'square')
    .maybeSingle();
  if (!pending) {
    return new Response(JSON.stringify({ error: 'no_pending_square_connection' }), { status: 404 });
  }

  // vault.decrypted_secrets isn't exposed over PostgREST — resolved through a
  // SECURITY DEFINER SQL function instead (get_pending_pos_secret), same
  // approach get_pos_credentials uses for the already-enabled case.
  const { data: accessToken } = await supabase.rpc('get_pending_pos_secret', {
    p_truck_id: truck.id,
    p_provider: 'square',
  });
  if (!accessToken) {
    return new Response(JSON.stringify({ error: 'token_not_found' }), { status: 500 });
  }

  let body: { location_id?: string };
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  if (!body.location_id) {
    // No location chosen yet — return the live list to pick from.
    const res = await fetch(`${squareApiBaseUrl(pending.environment)}/v2/locations`, {
      headers: { Authorization: `Bearer ${accessToken}`, 'Square-Version': '2025-01-23' },
    });
    if (!res.ok) {
      return new Response(JSON.stringify({ error: 'could_not_fetch_locations' }), { status: 502 });
    }
    const data = await res.json();
    const locations = ((data.locations ?? []) as { id: string; name: string }[]).map((l) => ({
      id: l.id,
      name: l.name,
    }));
    return new Response(JSON.stringify({ locations }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }

  const { error: updateError } = await supabase
    .from('pos_integrations')
    .update({ square_location_id: body.location_id, enabled: true })
    .eq('truck_id', truck.id)
    .eq('provider', 'square');
  if (updateError) {
    console.error('square-select-location finalize failed:', updateError);
    return new Response(JSON.stringify({ error: 'save_failed' }), { status: 500 });
  }

  return new Response(JSON.stringify({ success: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
});

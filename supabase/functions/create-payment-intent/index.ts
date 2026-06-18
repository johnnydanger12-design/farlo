import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function stripePost(path: string, params: Record<string, string>, secretKey: string) {
  const body = Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
  return fetch(`https://api.stripe.com/v1${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${secretKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response('Unauthorized', { status: 401 });
  }

  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!stripeKey) {
    return new Response(
      JSON.stringify({ error: 'Stripe not configured' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // Verify caller is authenticated
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return new Response('Unauthorized', { status: 401 });
  }

  let body: { truck_id: string; amount_cents: number };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { truck_id: truckId, amount_cents: amountCents } = body;
  if (!truckId || !amountCents || amountCents < 50) {
    return new Response(
      JSON.stringify({ error: 'truck_id and amount_cents (min 50) required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // Look up the truck owner's Stripe account
  const { data: truck, error: truckErr } = await supabase
    .from('food_trucks')
    .select('owner_id')
    .eq('id', truckId)
    .single();

  if (truckErr || !truck) {
    return new Response(
      JSON.stringify({ error: 'truck_not_found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: profile, error: profileErr } = await supabase
    .from('profiles')
    .select('stripe_account_id')
    .eq('id', truck.owner_id)
    .single();

  if (profileErr || !profile?.stripe_account_id) {
    return new Response(
      JSON.stringify({ error: 'owner_stripe_not_connected' }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const piRes = await stripePost('/payment_intents', {
    amount: String(amountCents),
    currency: 'usd',
    'payment_method_types[]': 'card',
    'transfer_data[destination]': profile.stripe_account_id,
  }, stripeKey);

  const pi = await piRes.json();
  if (!piRes.ok) {
    console.error('Stripe PaymentIntent error:', pi);
    return new Response(
      JSON.stringify({ error: pi.error?.message ?? 'stripe_error' }),
      { status: 502, headers: { 'Content-Type': 'application/json' } },
    );
  }

  return new Response(
    JSON.stringify({ client_secret: pi.client_secret, payment_intent_id: pi.id }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});

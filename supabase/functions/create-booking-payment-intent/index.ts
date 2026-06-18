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
  if (!authHeader) return new Response('Unauthorized', { status: 401 });

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
  if (authError || !user) return new Response('Unauthorized', { status: 401 });

  let body: { type: string; record_id: string; booking_id: string; amount_cents: number };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { type, record_id, booking_id, amount_cents } = body;
  if (!type || !record_id || !booking_id || !amount_cents || amount_cents < 50) {
    return new Response(
      JSON.stringify({ error: 'type, record_id, booking_id, and amount_cents (min 50) required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }
  if (type !== 'deposit' && type !== 'invoice') {
    return new Response(
      JSON.stringify({ error: 'type must be "deposit" or "invoice"' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // Verify caller is the consumer on this booking
  const { data: booking, error: bookingErr } = await supabase
    .from('event_booking_requests')
    .select('requester_id, truck_id')
    .eq('id', booking_id)
    .single();

  if (bookingErr || !booking) {
    return new Response(
      JSON.stringify({ error: 'booking_not_found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }
  if (booking.requester_id !== user.id) {
    return new Response('Forbidden', { status: 403 });
  }

  // Get the truck owner's Stripe Connect account
  const { data: truck } = await supabase
    .from('food_trucks')
    .select('owner_id')
    .eq('id', booking.truck_id)
    .single();

  const { data: profile } = await supabase
    .from('profiles')
    .select('stripe_account_id')
    .eq('id', truck?.owner_id)
    .single();

  if (!profile?.stripe_account_id) {
    return new Response(
      JSON.stringify({ error: 'owner_stripe_not_connected' }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const piRes = await stripePost('/payment_intents', {
    amount: String(amount_cents),
    currency: 'usd',
    'payment_method_types[]': 'card',
    'transfer_data[destination]': profile.stripe_account_id,
    'metadata[type]': type,
    'metadata[record_id]': record_id,
    'metadata[booking_id]': booking_id,
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

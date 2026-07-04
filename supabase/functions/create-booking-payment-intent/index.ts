import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function stripePost(
  path: string,
  params: Record<string, string>,
  secretKey: string,
  idempotencyKey?: string,
) {
  const body = Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
  return fetch(`https://api.stripe.com/v1${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${secretKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
      ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
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

  let body: { type: string; record_id: string; booking_id: string; idempotency_key?: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { type, record_id, booking_id, idempotency_key: idempotencyKey } = body;
  if (!type || !record_id || !booking_id) {
    return new Response(
      JSON.stringify({ error: 'type, record_id, and booking_id required' }),
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

  // Recompute the charge amount server-side from the real stored deposit/quote
  // amount — never trust a client-supplied amount_cents. Previously this function
  // took the amount directly from the client, letting anyone mark a real
  // high-value quote/deposit "paid" for an arbitrary amount (Phase 2 audit,
  // Critical Finding #1).
  let amountCents: number;
  if (type === 'deposit') {
    const { data: deposit, error: depositErr } = await supabase
      .from('booking_deposits')
      .select('amount, booking_id, status')
      .eq('id', record_id)
      .single();
    if (depositErr || !deposit || deposit.booking_id !== booking_id) {
      return new Response(
        JSON.stringify({ error: 'deposit_not_found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } },
      );
    }
    if (deposit.status === 'paid') {
      return new Response(
        JSON.stringify({ error: 'deposit_already_paid' }),
        { status: 409, headers: { 'Content-Type': 'application/json' } },
      );
    }
    amountCents = Math.round(Number(deposit.amount) * 100);
  } else {
    const { data: quote, error: quoteErr } = await supabase
      .from('booking_quotes')
      .select('amount, booking_id, status, type')
      .eq('id', record_id)
      .single();
    if (quoteErr || !quote || quote.booking_id !== booking_id || quote.type !== 'invoice') {
      return new Response(
        JSON.stringify({ error: 'invoice_not_found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } },
      );
    }
    if (quote.status === 'paid') {
      return new Response(
        JSON.stringify({ error: 'invoice_already_paid' }),
        { status: 409, headers: { 'Content-Type': 'application/json' } },
      );
    }
    amountCents = Math.round(Number(quote.amount) * 100);
  }

  if (amountCents < 50) {
    return new Response(
      JSON.stringify({ error: 'amount is below the minimum chargeable amount' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // Get the truck owner's Stripe Connect account
  const { data: truck } = await supabase
    .from('food_trucks')
    .select('owner_id')
    .eq('id', booking.truck_id)
    .single();

  // Same subscription-lapse recheck as create-payment-intent — a lapsed truck
  // should not be able to keep collecting booking deposit/invoice payments
  // either (bugs.md Executive Summary #4).
  const { data: hasSub } = await supabase.rpc('owner_has_active_subscription', {
    p_owner_id: truck?.owner_id,
  });
  if (!hasSub) {
    return new Response(
      JSON.stringify({ error: 'truck_subscription_inactive' }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
    );
  }

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

  // Same idempotency-key reasoning as create-payment-intent — a retry of the
  // same payment attempt reuses this PaymentIntent instead of double-charging.
  const piRes = await stripePost('/payment_intents', {
    amount: String(amountCents),
    currency: 'usd',
    'payment_method_types[]': 'card',
    'transfer_data[destination]': profile.stripe_account_id,
    'metadata[type]': type,
    'metadata[record_id]': record_id,
    'metadata[booking_id]': booking_id,
  }, stripeKey, idempotencyKey);

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

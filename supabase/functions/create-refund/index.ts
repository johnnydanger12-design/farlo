import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

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

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return new Response('Unauthorized', { status: 401 });
  }

  let body: { order_id: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { order_id: orderId } = body;
  if (!orderId) {
    return new Response(
      JSON.stringify({ error: 'order_id required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('stripe_payment_intent_id, payment_status, consumer_id, truck_id')
    .eq('id', orderId)
    .single();

  if (orderErr || !order) {
    return new Response(
      JSON.stringify({ error: 'order_not_found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  if (order.payment_status !== 'paid') {
    return new Response(
      JSON.stringify({ error: 'order_not_paid' }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
    );
  }

  if (!order.stripe_payment_intent_id) {
    return new Response(
      JSON.stringify({ error: 'no_payment_intent' }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // Verify caller is either the consumer or the truck owner
  const isConsumer = order.consumer_id === user.id;
  if (!isConsumer) {
    const { data: truck } = await supabase
      .from('food_trucks')
      .select('owner_id')
      .eq('id', order.truck_id)
      .single();
    if (truck?.owner_id !== user.id) {
      return new Response('Forbidden', { status: 403 });
    }
  }

  // Issue refund via Stripe
  const refundBody = `payment_intent=${encodeURIComponent(order.stripe_payment_intent_id)}`;
  const refundRes = await fetch('https://api.stripe.com/v1/refunds', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: refundBody,
  });

  const refund = await refundRes.json();
  if (!refundRes.ok) {
    console.error('Stripe refund error:', refund);
    return new Response(
      JSON.stringify({ error: refund.error?.message ?? 'stripe_error' }),
      { status: 502, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // Update immediately — stripe-webhook will also confirm via charge.refunded event
  await supabase
    .from('orders')
    .update({ payment_status: 'refunded' })
    .eq('id', orderId);

  return new Response(
    JSON.stringify({ refunded: true }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});

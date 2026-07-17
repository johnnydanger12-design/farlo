import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { computeOrderAmountCents, MenuItemMismatchError, ModifierMismatchError } from './pricing.ts';

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

  let body: {
    truck_id: string;
    items: { menu_item_id: string; quantity: number; added_modifier_ids?: string[] }[];
    idempotency_key?: string;
  };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { truck_id: truckId, items, idempotency_key: idempotencyKey } = body;
  if (!truckId || !Array.isArray(items) || items.length === 0) {
    return new Response(
      JSON.stringify({ error: 'truck_id and a non-empty items array are required' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }
  for (const it of items) {
    if (!it.menu_item_id || !Number.isInteger(it.quantity) || it.quantity < 1) {
      return new Response(
        JSON.stringify({ error: 'each item requires menu_item_id and a positive integer quantity' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      );
    }
  }

  // Recompute the charge amount server-side from real menu_items prices — never
  // trust a client-supplied amount_cents. Previously this function took the total
  // directly from the client, letting anyone pay an arbitrary amount for a real
  // order (Phase 2 audit, Critical Finding #1).
  const menuItemIds = [...new Set(items.map((i) => i.menu_item_id))];
  const { data: menuItems, error: menuErr } = await supabase
    .from('menu_items')
    .select('id, price, truck_id')
    .in('id', menuItemIds);

  if (menuErr || !menuItems || menuItems.length !== menuItemIds.length) {
    return new Response(
      JSON.stringify({ error: 'one or more menu items were not found' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const modifierIds = [...new Set(items.flatMap((i) => i.added_modifier_ids ?? []))];
  let modifiers: { id: string; menu_item_id: string; price_delta: number | string }[] = [];
  if (modifierIds.length > 0) {
    const { data: modifierRows, error: modifierErr } = await supabase
      .from('menu_item_modifiers')
      .select('id, menu_item_id, price_delta')
      .in('id', modifierIds);
    if (modifierErr || !modifierRows || modifierRows.length !== modifierIds.length) {
      return new Response(
        JSON.stringify({ error: 'one or more modifiers were not found' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      );
    }
    modifiers = modifierRows;
  }

  let amountCents: number;
  try {
    amountCents = computeOrderAmountCents(items, menuItems, modifiers, truckId);
  } catch (e) {
    if (e instanceof MenuItemMismatchError || e instanceof ModifierMismatchError) {
      return new Response(
        JSON.stringify({ error: e.message }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      );
    }
    throw e;
  }

  // Look up the truck owner's Stripe account + their own tax rate — each
  // business sets their own rate (varies by city/county), not something we can
  // read off Clover or any other external source of truth.
  const { data: truck, error: truckErr } = await supabase
    .from('food_trucks')
    .select('owner_id, tax_rate_percent')
    .eq('id', truckId)
    .single();

  if (truckErr || !truck) {
    return new Response(
      JSON.stringify({ error: 'truck_not_found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const taxRatePercent = Number(truck.tax_rate_percent) || 0;
  const taxCents = Math.round(amountCents * (taxRatePercent / 100));
  const totalCents = amountCents + taxCents;

  if (totalCents < 50) {
    return new Response(
      JSON.stringify({ error: 'order total is below the minimum chargeable amount' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // A lapsed subscription now hides the truck from the public map (RLS), but a
  // consumer who already has the truck_id (favorited earlier, deep link, or a
  // direct API call) could otherwise still pay this truck's owner indefinitely
  // after their subscription lapsed (bugs.md Executive Summary #4). This check
  // cannot be bypassed by the client, unlike the map-visibility filter alone.
  const { data: hasSub } = await supabase.rpc('owner_has_active_subscription', {
    p_owner_id: truck.owner_id,
  });
  if (!hasSub) {
    return new Response(
      JSON.stringify({ error: 'truck_subscription_inactive' }),
      { status: 422, headers: { 'Content-Type': 'application/json' } },
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

  // Idempotency-Key: a retry of the same checkout attempt (network blip,
  // user re-tapping Pay after an error) reuses the same PaymentIntent instead
  // of creating a second real charge. Scoped per-request by the client
  // generating one key per checkout attempt and reusing it across retries of
  // that same attempt (bugs.md Executive Summary #3 — stranded charge with no
  // idempotency key, inviting an immediate double-charge retry).
  const piRes = await stripePost('/payment_intents', {
    amount: String(totalCents),
    currency: 'usd',
    'payment_method_types[]': 'card',
    'transfer_data[destination]': profile.stripe_account_id,
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
    JSON.stringify({
      client_secret: pi.client_secret,
      payment_intent_id: pi.id,
      subtotal_cents: amountCents,
      tax_cents: taxCents,
      total_cents: totalCents,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});

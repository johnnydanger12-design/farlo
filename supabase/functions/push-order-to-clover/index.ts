// Pushes a newly-placed Farlo order into a truck's Clover account (order +
// line items + a print trigger for their order printer), for trucks that
// have a Clover integration configured in pos_integrations. Triggered by a
// Postgres AFTER INSERT trigger on `orders` (push_order_to_clover(), see
// migration 20260715220000) via pg_net — not called by the Flutter app.
//
// Auth: reuses the same agent_cron_bearer/AGENT_EMAIL_SECRET shared-secret
// pattern every cron-triggered agent function already uses (requireAgentSecret)
// rather than minting a new secret just for this.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret } from '../_shared/auth.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function cloverBaseUrl(environment: string): string {
  return environment === 'sandbox' ? 'https://apisandbox.dev.clover.com' : 'https://api.clover.com';
}

async function logAttempt(orderId: string, truckId: string, success: boolean, error?: string) {
  try {
    await supabase.from('pos_push_attempts').insert({
      order_id: orderId,
      truck_id: truckId,
      provider: 'clover',
      success,
      error: error ?? null,
    });
  } catch (err) {
    // Best-effort — never let logging itself fail the request.
    console.error('Failed to log pos_push_attempts row:', err);
  }
}

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  let body: { order_id: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }
  const orderId = body.order_id;
  if (!orderId) return new Response(JSON.stringify({ error: 'order_id required' }), { status: 400 });

  const { data: order, error: orderError } = await supabase
    .from('orders')
    .select('id, truck_id, order_items(menu_item_name, menu_item_price, quantity)')
    .eq('id', orderId)
    .single();

  if (orderError || !order) {
    console.error('push-order-to-clover: order not found', orderId, orderError);
    return new Response(JSON.stringify({ error: 'order_not_found' }), { status: 404 });
  }

  const { data: creds } = await supabase.rpc('get_clover_credentials', { p_truck_id: order.truck_id });
  const credentials = Array.isArray(creds) ? creds[0] : creds;

  if (!credentials) {
    // Shouldn't happen — the DB trigger only fires this function when an
    // enabled integration exists — but no-op cleanly if it does (e.g. a race
    // where the integration was disabled between the trigger firing and now).
    return new Response(JSON.stringify({ skipped: true }), { status: 200 });
  }

  const baseUrl = cloverBaseUrl(credentials.environment);
  const authHeaders = {
    Authorization: `Bearer ${credentials.api_token}`,
    'Content-Type': 'application/json',
  };

  try {
    // 1. Create an empty order.
    const orderBody: Record<string, unknown> = { state: 'Open', currency: 'USD' };
    if (credentials.clover_order_type_id) {
      orderBody.orderType = { id: credentials.clover_order_type_id };
    }
    const createRes = await fetch(`${baseUrl}/v3/merchants/${credentials.external_merchant_id}/orders`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify(orderBody),
    });
    if (!createRes.ok) {
      throw new Error(`Clover order create failed (${createRes.status}): ${await createRes.text()}`);
    }
    const cloverOrder = await createRes.json();
    const cloverOrderId = cloverOrder.id;

    // 2. Add every order_items row as a line item, in one bulk call.
    const items = (order.order_items ?? []).map((i: { menu_item_name: string; menu_item_price: number; quantity: number }) => ({
      name: i.menu_item_name,
      price: Math.round(i.menu_item_price * 100), // Clover prices are integer cents
      // unitQty is a fixed-point integer scaled by 1000 (1000 = 1 whole unit) —
      // confirmed empirically against a real sandbox order: sending the raw
      // quantity (e.g. 2) displayed as "0.002" and priced the line item at
      // essentially $0, not quantity 2.
      unitQty: i.quantity * 1000,
    }));
    if (items.length > 0) {
      const lineItemsRes = await fetch(
        `${baseUrl}/v3/merchants/${credentials.external_merchant_id}/orders/${cloverOrderId}/bulk_line_items`,
        { method: 'POST', headers: authHeaders, body: JSON.stringify({ items }) },
      );
      if (!lineItemsRes.ok) {
        throw new Error(`Clover line items create failed (${lineItemsRes.status}): ${await lineItemsRes.text()}`);
      }
    }

    // 3. Trigger a print event — unconditional rather than relying on the
    // merchant's own Register auto-print setting, which we don't control.
    const printRes = await fetch(`${baseUrl}/v3/merchants/${credentials.external_merchant_id}/print_event`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({ orderRef: { id: cloverOrderId } }),
    });
    if (!printRes.ok) {
      // Order + line items already succeeded — a print failure is logged but
      // doesn't unwind those; the order still exists in Clover either way.
      await logAttempt(orderId, order.truck_id, false, `Order created but print failed (${printRes.status}): ${await printRes.text()}`);
      return new Response(JSON.stringify({ success: true, printed: false }), { status: 200 });
    }

    await logAttempt(orderId, order.truck_id, true);
    return new Response(JSON.stringify({ success: true, printed: true }), { status: 200 });
  } catch (err) {
    console.error('push-order-to-clover failed:', err);
    await logAttempt(orderId, order.truck_id, false, String(err));
    // Always 200 — this is a fire-and-forget webhook target invoked from a DB
    // trigger; a customer's order has already succeeded independent of this.
    return new Response(JSON.stringify({ success: false, error: String(err) }), { status: 200 });
  }
});

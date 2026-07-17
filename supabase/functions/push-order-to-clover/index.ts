// Handles order-automation for a newly-placed Farlo order: pushes it into a
// truck's Clover account (order + line items + a print trigger) if one is
// configured in pos_integrations, and/or auto-advances its status through
// accepted/"Preparing" -> ready -> completed per that truck's own
// auto_accept_orders/auto_mark_ready/auto_mark_complete settings. Triggered
// by a Postgres AFTER INSERT trigger on `orders` (push_order_to_clover(), see
// migration 20260717 broaden_order_automation_trigger) via pg_net — not
// called by the Flutter app. Despite the filename (kept to avoid an
// unnecessary rename), this now also drives auto-accept for non-Clover trucks.
//
// Auth: reuses the same agent_cron_bearer/AGENT_EMAIL_SECRET shared-secret
// pattern every cron-triggered agent function already uses (requireAgentSecret)
// rather than minting a new secret just for this.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret } from '../_shared/auth.ts';
import { notifyOrderStatus, notifyUser } from '../_shared/orderNotifications.ts';

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

async function notifyOwnerPrintFailed(ownerId: string | null, truckId: string, orderId: string) {
  if (!ownerId) return;
  await notifyUser(
    supabase,
    ownerId,
    'clover_print_failed',
    'Clover Print Failed',
    'A new order reached Clover but the print failed — check your Clover Station and Order Queue.',
    orderId,
  );
}

// Advances accepted -> ready (and further -> completed) per the truck's own
// flags, once "accepted"/"Preparing" has been reached — regardless of whether
// that happened via a Clover print or immediately on placement. Only fires the
// IMMEDIATE transition when that stage's delay is 0 — a nonzero delay means
// this stage is left entirely to the advance-delayed-orders cron instead, so
// there's exactly one place that ever performs a given transition.
async function cascadeFromAccepted(
  orderId: string,
  autoMarkReady: boolean,
  autoMarkReadyDelayMinutes: number,
  autoMarkComplete: boolean,
  autoMarkCompleteDelayMinutes: number,
) {
  if (!autoMarkReady || autoMarkReadyDelayMinutes > 0) return;
  const { data: readyRows } = await supabase
    .from('orders')
    .update({ status: 'ready', updated_at: new Date().toISOString() })
    .eq('id', orderId)
    .eq('status', 'accepted')
    .select('id');
  if (!readyRows || readyRows.length === 0) return;
  await notifyOrderStatus(supabase, 'order_ready', orderId);

  if (autoMarkComplete && autoMarkCompleteDelayMinutes === 0) {
    // No consumer notification on completion — matches the existing manual
    // "Mark Completed" flow, which is a silent close-out, not a customer alert.
    await supabase
      .from('orders')
      .update({ status: 'completed', updated_at: new Date().toISOString() })
      .eq('id', orderId)
      .eq('status', 'ready');
  }
}

// pending -> accepted/"Preparing", if it hasn't already moved. `eq('status', ...)`
// guards mirror the client's own conditional-update pattern
// (orders_repository.dart) so a concurrent cancellation isn't clobbered.
async function acceptOrder(
  orderId: string,
  autoMarkReady: boolean,
  autoMarkReadyDelayMinutes: number,
  autoMarkComplete: boolean,
  autoMarkCompleteDelayMinutes: number,
) {
  const { data: acceptedRows } = await supabase
    .from('orders')
    .update({ status: 'accepted', updated_at: new Date().toISOString() })
    .eq('id', orderId)
    .eq('status', 'pending')
    .select('id');
  if (!acceptedRows || acceptedRows.length === 0) return;
  await notifyOrderStatus(supabase, 'order_accepted', orderId);
  await cascadeFromAccepted(orderId, autoMarkReady, autoMarkReadyDelayMinutes, autoMarkComplete, autoMarkCompleteDelayMinutes);
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
    .select('id, truck_id, tax_price, pickup_note, order_items(menu_item_name, menu_item_price, quantity, removed_modifiers, added_modifiers), profiles(display_name)')
    .eq('id', orderId)
    .single();

  if (orderError || !order) {
    console.error('push-order-to-clover: order not found', orderId, orderError);
    return new Response(JSON.stringify({ error: 'order_not_found' }), { status: 404 });
  }

  const { data: truck } = await supabase
    .from('food_trucks')
    .select('auto_accept_orders, auto_mark_ready, auto_mark_ready_delay_minutes, auto_mark_complete, auto_mark_complete_delay_minutes, owner_id')
    .eq('id', order.truck_id)
    .single();
  const autoAccept = truck?.auto_accept_orders ?? false;
  const autoMarkReady = truck?.auto_mark_ready ?? false;
  const autoMarkReadyDelayMinutes = truck?.auto_mark_ready_delay_minutes ?? 0;
  const autoMarkComplete = truck?.auto_mark_complete ?? false;
  const autoMarkCompleteDelayMinutes = truck?.auto_mark_complete_delay_minutes ?? 0;

  const { data: creds } = await supabase.rpc('get_clover_credentials', { p_truck_id: order.truck_id });
  const credentials = Array.isArray(creds) ? creds[0] : creds;

  if (!credentials) {
    // No Clover integration — the only signal available is the order's own
    // placement, so auto-accept (if enabled) fires immediately.
    if (autoAccept) {
      await acceptOrder(orderId, autoMarkReady, autoMarkReadyDelayMinutes, autoMarkComplete, autoMarkCompleteDelayMinutes);
    }
    return new Response(JSON.stringify({ skipped: !autoAccept }), { status: 200 });
  }

  const baseUrl = cloverBaseUrl(credentials.environment);
  const authHeaders = {
    Authorization: `Bearer ${credentials.api_token}`,
    'Content-Type': 'application/json',
  };

  try {
    // 1. Create an empty order.
    // employee is set to a dedicated "Farlo" employee (created per-merchant in
    // their Clover dashboard) purely so the printed ticket shows a server name —
    // API-created orders otherwise print with no server name at all.
    // title is set to the customer's name so the ticket identifies whose order it is.
    const consumerName = (order.profiles as { display_name?: string } | null)?.display_name || 'Farlo Customer';
    const orderBody: Record<string, unknown> = {
      state: 'Open',
      currency: 'USD',
      title: consumerName,
      employee: { id: credentials.clover_employee_id },
    };
    if (credentials.clover_order_type_id) {
      orderBody.orderType = { id: credentials.clover_order_type_id };
    }
    // Pickup note (allergies, special requests, etc.) — without this, a
    // business with auto_accept_orders on may never open the Farlo app for
    // this order at all, so the printed ticket is the only place they'd ever
    // see it.
    if (order.pickup_note) {
      orderBody.note = order.pickup_note;
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
    // removed_modifiers/added_modifiers are appended to the item name so
    // kitchen staff see them on the printed ticket — without this, a business
    // with auto_accept_orders on may never open the Farlo app for this order
    // and would never see a customer's "no mustard"/"extra bacon" choices.
    // Added modifiers' price is folded into the unit price so the ticket
    // total still matches exactly what was actually charged (same principle
    // as the tax line item below).
    const items = (order.order_items ?? []).map((i: {
      menu_item_name: string;
      menu_item_price: number;
      quantity: number;
      removed_modifiers: string[] | null;
      added_modifiers: { name: string; price_delta: number }[] | null;
    }) => {
      const addedTotal = (i.added_modifiers ?? []).reduce((sum, m) => sum + Number(m.price_delta), 0);
      const modifierParts = [
        ...(i.removed_modifiers ?? []).map((name) => `No ${name}`),
        ...(i.added_modifiers ?? []).map((m) => `+ ${m.name}`),
      ];
      const name = modifierParts.length > 0
        ? `${i.menu_item_name} (${modifierParts.join(', ')})`
        : i.menu_item_name;
      return {
        name,
        price: Math.round((i.menu_item_price + addedTotal) * 100), // Clover prices are integer cents
        // unitQty is a fixed-point integer scaled by 1000 (1000 = 1 whole unit) —
        // confirmed empirically against a real sandbox order: sending the raw
        // quantity (e.g. 2) displayed as "0.002" and priced the line item at
        // essentially $0, not quantity 2.
        unitQty: i.quantity * 1000,
      };
    });
    // Tax is charged to the customer as part of the same Stripe PaymentIntent
    // (create-payment-intent, from the truck's own tax_rate_percent) — added
    // here as its own line item, not a Clover taxRates reference, so the
    // printed ticket total matches exactly what was actually charged
    // regardless of whether this merchant has any tax rate configured in Clover.
    if (order.tax_price > 0) {
      items.push({ name: 'Sales Tax', price: Math.round(order.tax_price * 100), unitQty: 1000 });
    }
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
      // Deliberately does NOT auto-accept here even if enabled — a failed
      // print means the kitchen never actually saw it, so the order stays
      // 'pending' in the owner's queue as a safety net, and the owner is
      // alerted directly rather than the failure being silent.
      const errorDetail = `Order created but print failed (${printRes.status}): ${await printRes.text()}`;
      await logAttempt(orderId, order.truck_id, false, errorDetail);
      await notifyOwnerPrintFailed(truck?.owner_id ?? null, order.truck_id, orderId);
      return new Response(JSON.stringify({ success: true, printed: false }), { status: 200 });
    }

    await logAttempt(orderId, order.truck_id, true);

    // A successful print IS the owner accepting and preparing the order — the
    // most reliable "they've seen it" signal available for a Clover-integrated
    // truck, so auto-accept (if enabled) gates on this rather than firing
    // immediately on placement the way a non-integrated truck's does.
    if (autoAccept) {
      await acceptOrder(orderId, autoMarkReady, autoMarkReadyDelayMinutes, autoMarkComplete, autoMarkCompleteDelayMinutes);
    }

    return new Response(JSON.stringify({ success: true, printed: true }), { status: 200 });
  } catch (err) {
    console.error('push-order-to-clover failed:', err);
    await logAttempt(orderId, order.truck_id, false, String(err));
    // Always 200 — this is a fire-and-forget webhook target invoked from a DB
    // trigger; a customer's order has already succeeded independent of this.
    return new Response(JSON.stringify({ success: false, error: String(err) }), { status: 200 });
  }
});

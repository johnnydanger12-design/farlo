// Handles order-automation for a newly-placed Farlo order: pushes it into a
// truck's connected POS (Clover, Square, ...) via the resolved provider
// adapter (order + line items + a fulfillment trigger) if one is configured
// in pos_integrations, and/or auto-advances its status through
// accepted/"Preparing" -> ready -> completed per that truck's own
// auto_accept_orders/auto_mark_ready/auto_mark_complete settings. Triggered
// by a Postgres AFTER INSERT trigger on `orders` (push_order_to_pos(), see
// migration 20260722030210_rename_push_order_to_pos_trigger) via pg_net — not
// called by the Flutter app. Renamed from push-order-to-clover now that it's
// a real multi-provider dispatcher, not Clover-specific.
//
// Auth: reuses the same agent_cron_bearer/AGENT_EMAIL_SECRET shared-secret
// pattern every cron-triggered agent function already uses (requireAgentSecret)
// rather than minting a new secret just for this.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret } from '../_shared/auth.ts';
import { notifyOrderStatus, notifyUser } from '../_shared/orderNotifications.ts';
import { getAdapter, type PosCredentials, type PosOrder } from '../_shared/posAdapters/index.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

async function logAttempt(orderId: string, truckId: string, provider: string, success: boolean, error?: string) {
  try {
    await supabase.from('pos_push_attempts').insert({
      order_id: orderId,
      truck_id: truckId,
      provider,
      success,
      error: error ?? null,
    });
  } catch (err) {
    // Best-effort — never let logging itself fail the request.
    console.error('Failed to log pos_push_attempts row:', err);
  }
}

async function notifyOwnerPushFailed(ownerId: string | null, truckId: string, orderId: string) {
  if (!ownerId) return;
  await notifyUser(
    supabase,
    ownerId,
    'clover_print_failed',
    'Order Reached Your POS, But Fulfillment Failed',
    'A new order reached your POS but fulfillment failed — check your POS device and Order Queue.',
    orderId,
  );
}

// Advances accepted -> ready (and further -> completed) per the truck's own
// flags, once "accepted"/"Preparing" has been reached — regardless of whether
// that happened via a POS fulfillment trigger or immediately on placement.
// Only fires the IMMEDIATE transition when that stage's delay is 0 — a
// nonzero delay means this stage is left entirely to the advance-delayed-orders
// cron instead, so there's exactly one place that ever performs a given transition.
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

  const { data: orderRow, error: orderError } = await supabase
    .from('orders')
    .select('id, truck_id, tax_price, pickup_note, order_items(menu_item_name, menu_item_price, quantity, removed_modifiers, added_modifiers), profiles(display_name, phone)')
    .eq('id', orderId)
    .single();

  if (orderError || !orderRow) {
    console.error('push-order-to-pos: order not found', orderId, orderError);
    return new Response(JSON.stringify({ error: 'order_not_found' }), { status: 404 });
  }

  const { data: truck } = await supabase
    .from('food_trucks')
    .select('auto_accept_orders, auto_mark_ready, auto_mark_ready_delay_minutes, auto_mark_complete, auto_mark_complete_delay_minutes, owner_id')
    .eq('id', orderRow.truck_id)
    .single();
  const autoAccept = truck?.auto_accept_orders ?? false;
  const autoMarkReady = truck?.auto_mark_ready ?? false;
  const autoMarkReadyDelayMinutes = truck?.auto_mark_ready_delay_minutes ?? 0;
  const autoMarkComplete = truck?.auto_mark_complete ?? false;
  const autoMarkCompleteDelayMinutes = truck?.auto_mark_complete_delay_minutes ?? 0;

  const { data: credsRows } = await supabase.rpc('get_pos_credentials', { p_truck_id: orderRow.truck_id });
  const credentials = (Array.isArray(credsRows) ? credsRows[0] : credsRows) as PosCredentials | null;

  if (!credentials) {
    // No POS integration — the only signal available is the order's own
    // placement, so auto-accept (if enabled) fires immediately.
    if (autoAccept) {
      await acceptOrder(orderId, autoMarkReady, autoMarkReadyDelayMinutes, autoMarkComplete, autoMarkCompleteDelayMinutes);
    }
    return new Response(JSON.stringify({ skipped: !autoAccept }), { status: 200 });
  }

  const adapter = getAdapter(credentials.provider);
  const consumerProfile = orderRow.profiles as { display_name?: string; phone?: string } | null;
  const order: PosOrder = {
    id: orderRow.id,
    truck_id: orderRow.truck_id,
    tax_price: orderRow.tax_price,
    pickup_note: orderRow.pickup_note,
    consumer_name: consumerProfile?.display_name || 'Farlo Customer',
    consumer_phone: consumerProfile?.phone ?? null,
    order_items: orderRow.order_items ?? [],
  };

  try {
    // Associates this order with a POS customer record (matched/created by
    // phone) so it counts toward the merchant's own loyalty program, same as
    // an in-person phone-number entry. No-op if the customer collected no
    // phone at checkout, or if the lookup/create fails for any reason.
    const customerId = order.consumer_phone
      ? await adapter.findOrCreateCustomer(order.consumer_phone, credentials)
      : null;

    const externalOrderId = await adapter.createOrder(order, credentials, customerId);
    await adapter.addLineItems(externalOrderId, order, credentials);
    const fulfillment = await adapter.triggerFulfillment(externalOrderId, credentials);

    if (!fulfillment.success) {
      await logAttempt(orderId, order.truck_id, credentials.provider, false, fulfillment.error);
      if (adapter.requiresFulfillmentConfirmation) {
        // Order + line items already succeeded — a fulfillment-trigger
        // failure is logged but doesn't unwind those; the order still exists
        // in the POS either way. Deliberately does NOT auto-accept here even
        // if enabled — the kitchen never actually saw it (this provider's
        // fulfillment trigger IS the "they've seen it" signal), so the order
        // stays 'pending' in the owner's queue as a safety net, and the owner
        // is alerted directly rather than the failure being silent.
        await notifyOwnerPushFailed(truck?.owner_id ?? null, order.truck_id, orderId);
        return new Response(JSON.stringify({ success: true, fulfilled: false }), { status: 200 });
      }
      // This provider has no fulfillment-confirmation signal to gate on, so a
      // trigger failure here is just a technical hiccup, not proof the
      // kitchen missed it — auto-accept still fires the same as it would for
      // a non-integrated truck.
      if (autoAccept) {
        await acceptOrder(orderId, autoMarkReady, autoMarkReadyDelayMinutes, autoMarkComplete, autoMarkCompleteDelayMinutes);
      }
      return new Response(JSON.stringify({ success: true, fulfilled: false }), { status: 200 });
    }

    await logAttempt(orderId, order.truck_id, credentials.provider, true);

    // A successful fulfillment trigger IS the owner accepting and preparing
    // the order — the most reliable "they've seen it" signal available for a
    // POS-integrated truck, so auto-accept (if enabled) gates on this rather
    // than firing immediately on placement the way a non-integrated truck's does.
    if (autoAccept) {
      await acceptOrder(orderId, autoMarkReady, autoMarkReadyDelayMinutes, autoMarkComplete, autoMarkCompleteDelayMinutes);
    }

    return new Response(JSON.stringify({ success: true, fulfilled: true }), { status: 200 });
  } catch (err) {
    console.error('push-order-to-pos failed:', err);
    await logAttempt(orderId, order.truck_id, credentials.provider, false, String(err));
    // Always 200 — this is a fire-and-forget webhook target invoked from a DB
    // trigger; a customer's order has already succeeded independent of this.
    return new Response(JSON.stringify({ success: false, error: String(err) }), { status: 200 });
  }
});

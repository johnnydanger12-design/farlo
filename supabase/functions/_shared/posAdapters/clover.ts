// Clover adapter — extracted from the original push-order-to-clover/index.ts
// with no behavior change (pure code-shape move) so Hope's live account keeps
// working identically after the multi-provider dispatcher refactor.
import type { PosAdapter, PosCredentials, PosOrder } from './types.ts';

function cloverBaseUrl(environment: string): string {
  return environment === 'sandbox' ? 'https://apisandbox.dev.clover.com' : 'https://api.clover.com';
}

function authHeaders(credentials: PosCredentials): Record<string, string> {
  return {
    Authorization: `Bearer ${credentials.decrypted_secret}`,
    'Content-Type': 'application/json',
  };
}

// Finds (or creates) a Clover Customer by phone number, so this order counts
// toward the merchant's own Clover Rewards loyalty points, same as an
// in-person phone-number entry would. Best-effort: the Customers API needs a
// broader-scoped token than Orders+Print (unverified against a real account
// as of this writing — every relevant endpoint 401s under Hope's current
// token). Any failure here must never break the order push itself, so this
// always returns null instead of throwing.
async function findOrCreateCustomer(phone: string, credentials: PosCredentials): Promise<string | null> {
  const baseUrl = cloverBaseUrl(credentials.environment);
  const merchantId = credentials.external_merchant_id;
  const headers = authHeaders(credentials);
  try {
    const searchRes = await fetch(
      `${baseUrl}/v3/merchants/${merchantId}/customers?filter=phoneNumber=${encodeURIComponent(phone)}`,
      { headers },
    );
    if (searchRes.ok) {
      const searchBody = await searchRes.json();
      const existing = searchBody?.elements?.[0];
      if (existing?.id) return existing.id;
    }

    const createRes = await fetch(`${baseUrl}/v3/merchants/${merchantId}/customers`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ phoneNumbers: [{ phoneNumber: phone }] }),
    });
    if (!createRes.ok) {
      console.error(`Clover customer create failed (${createRes.status}): ${await createRes.text()}`);
      return null;
    }
    const created = await createRes.json();
    return created?.id ?? null;
  } catch (err) {
    console.error('findOrCreateCustomer (clover) failed:', err);
    return null;
  }
}

// Creates an empty order.
// employee is set to a dedicated "Farlo" employee (created per-merchant in
// their Clover dashboard) purely so the printed ticket shows a server name —
// API-created orders otherwise print with no server name at all.
// title leads with the pickup code (the same code the customer sees in-app
// and in their receipt email) so staff can actually call it out at pickup —
// without it here, the printed ticket has no way to be matched back to what
// the customer is listening for.
async function createOrder(order: PosOrder, credentials: PosCredentials, customerId: string | null): Promise<string> {
  const baseUrl = cloverBaseUrl(credentials.environment);
  const headers = authHeaders(credentials);

  const orderBody: Record<string, unknown> = {
    state: 'Open',
    currency: 'USD',
    title: `#${order.pickup_code} — ${order.consumer_name}`,
    employee: { id: credentials.clover_employee_id },
  };
  if (credentials.clover_order_type_id) {
    orderBody.orderType = { id: credentials.clover_order_type_id };
  }
  if (customerId) {
    orderBody.customers = [{ id: customerId }];
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
    headers,
    body: JSON.stringify(orderBody),
  });
  if (!createRes.ok) {
    throw new Error(`Clover order create failed (${createRes.status}): ${await createRes.text()}`);
  }
  const cloverOrder = await createRes.json();
  return cloverOrder.id;
}

// Adds every order_items row as a line item, in one bulk call.
// removed_modifiers/added_modifiers are appended to the item name so kitchen
// staff see them on the printed ticket — without this, a business with
// auto_accept_orders on may never open the Farlo app for this order and would
// never see a customer's "no mustard"/"extra bacon" choices. Added modifiers'
// price is folded into the unit price so the ticket total still matches
// exactly what was actually charged (same principle as the tax line item below).
async function addLineItems(externalOrderId: string, order: PosOrder, credentials: PosCredentials): Promise<void> {
  const baseUrl = cloverBaseUrl(credentials.environment);
  const headers = authHeaders(credentials);

  const items = order.order_items.map((i) => {
    const addedTotal = (i.added_modifiers ?? []).reduce((sum, m) => sum + Number(m.price_delta), 0)
      + (i.selected_options ?? []).reduce((sum, m) => sum + Number(m.price_delta), 0);
    const modifierParts = [
      ...(i.removed_modifiers ?? []).map((name) => `No ${name}`),
      ...(i.added_modifiers ?? []).map((m) => `+ ${m.name}`),
      // Required single-select group choices (e.g. "Toast" for Choice of
      // Bread) — just the chosen option's name, no "+"/"No" prefix, since
      // it's a plain selection rather than an addition or removal.
      ...(i.selected_options ?? []).map((m) => m.name),
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
  // printed ticket total matches exactly what was actually charged regardless
  // of whether this merchant has any tax rate configured in Clover.
  if (order.tax_price > 0) {
    items.push({ name: 'Sales Tax', price: Math.round(order.tax_price * 100), unitQty: 1000 });
  }
  if (items.length === 0) return;

  const lineItemsRes = await fetch(
    `${baseUrl}/v3/merchants/${credentials.external_merchant_id}/orders/${externalOrderId}/bulk_line_items`,
    { method: 'POST', headers, body: JSON.stringify({ items }) },
  );
  if (!lineItemsRes.ok) {
    throw new Error(`Clover line items create failed (${lineItemsRes.status}): ${await lineItemsRes.text()}`);
  }
}

// Triggers a print event — unconditional rather than relying on the
// merchant's own Register auto-print setting, which we don't control.
async function triggerFulfillment(
  externalOrderId: string,
  credentials: PosCredentials,
): Promise<{ success: boolean; error?: string }> {
  const baseUrl = cloverBaseUrl(credentials.environment);
  const headers = authHeaders(credentials);

  const printRes = await fetch(`${baseUrl}/v3/merchants/${credentials.external_merchant_id}/print_event`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ orderRef: { id: externalOrderId } }),
  });
  if (!printRes.ok) {
    return { success: false, error: `Order created but print failed (${printRes.status}): ${await printRes.text()}` };
  }
  return { success: true };
}

export const cloverAdapter: PosAdapter = {
  requiresFulfillmentConfirmation: true,
  findOrCreateCustomer,
  createOrder,
  addLineItems,
  triggerFulfillment,
};

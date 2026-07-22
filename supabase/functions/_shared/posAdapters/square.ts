// Square adapter — scaffold only (Phase 2). No real Square Application exists
// yet (Johnny needs to create one in Square's Developer Dashboard before the
// OAuth flow can be built/tested), so this can't be exercised end-to-end yet.
// Square has no Clover-print equivalent, so requiresFulfillmentConfirmation is
// a best guess (false) pending real-account verification.
import type { PosAdapter, PosCredentials, PosOrder } from './types.ts';

function squareBaseUrl(environment: string): string {
  return environment === 'sandbox' ? 'https://connect.squareupsandbox.com' : 'https://connect.squareup.com';
}

function authHeaders(credentials: PosCredentials): Record<string, string> {
  return {
    Authorization: `Bearer ${credentials.decrypted_secret}`,
    'Content-Type': 'application/json',
    'Square-Version': '2025-01-23',
  };
}

// Square loyalty is out of scope for this build.
async function findOrCreateCustomer(_phone: string, _credentials: PosCredentials): Promise<string | null> {
  return null;
}

async function createOrder(order: PosOrder, credentials: PosCredentials, _customerId: string | null): Promise<string> {
  const baseUrl = squareBaseUrl(credentials.environment);
  const headers = authHeaders(credentials);

  const lineItems = order.order_items.map((i) => {
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
      quantity: String(i.quantity),
      base_price_money: { amount: Math.round((i.menu_item_price + addedTotal) * 100), currency: 'USD' },
    };
  });
  if (order.tax_price > 0) {
    lineItems.push({
      name: 'Sales Tax',
      quantity: '1',
      base_price_money: { amount: Math.round(order.tax_price * 100), currency: 'USD' },
    });
  }

  const res = await fetch(`${baseUrl}/v2/orders`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      idempotency_key: crypto.randomUUID(),
      order: {
        location_id: credentials.square_location_id,
        line_items: lineItems,
        note: order.pickup_note ?? undefined,
      },
    }),
  });
  if (!res.ok) {
    throw new Error(`Square order create failed (${res.status}): ${await res.text()}`);
  }
  const body = await res.json();
  return body.order.id;
}

// Square's create-order call already includes line items in one request, so
// this is a no-op — kept only to satisfy the shared PosAdapter interface.
async function addLineItems(): Promise<void> {}

// Square has no known print/fulfillment-confirmation equivalent to Clover's
// print_event. Treated as an immediate no-op success until real OAuth access
// exists to verify against a live account.
async function triggerFulfillment(): Promise<{ success: boolean; error?: string }> {
  return { success: true };
}

export const squareAdapter: PosAdapter = {
  requiresFulfillmentConfirmation: false,
  findOrCreateCustomer,
  createOrder,
  addLineItems,
  triggerFulfillment,
};

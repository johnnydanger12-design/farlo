// Provider-agnostic shapes shared by every POS adapter. The dispatcher
// (push-order-to-pos/index.ts) orchestrates calls against whichever adapter
// `getAdapter(credentials.provider)` resolves to; each adapter file owns every
// provider-specific request shape/quirk internally.

export interface PosCredentials {
  provider: string;
  external_merchant_id: string;
  decrypted_secret: string;
  refresh_token: string | null;
  token_expires_at: string | null;
  clover_order_type_id: string | null;
  clover_employee_id: string | null;
  square_location_id: string | null;
  environment: string;
}

export interface PosOrderItem {
  menu_item_name: string;
  menu_item_price: number;
  quantity: number;
  removed_modifiers: string[] | null;
  added_modifiers: { name: string; price_delta: number }[] | null;
}

export interface PosOrder {
  id: string;
  truck_id: string;
  tax_price: number;
  pickup_note: string | null;
  consumer_name: string;
  consumer_phone: string | null;
  order_items: PosOrderItem[];
}

export interface PosAdapter {
  // Whether a successful triggerFulfillment call is the "owner has seen this"
  // signal auto-accept should gate on (Clover: yes, via a print event — the
  // only reliable proof the kitchen saw it). A provider with no such signal
  // should set this false so auto-accept fires immediately once pushed,
  // matching how a non-integrated truck already behaves.
  requiresFulfillmentConfirmation: boolean;

  // Best-effort loyalty lookup/creation by phone. Must never throw — return
  // null on any failure so it can never break the order push itself.
  findOrCreateCustomer(phone: string, credentials: PosCredentials): Promise<string | null>;

  // Creates the order shell (optionally linked to customerId) and returns the
  // provider's external order id.
  createOrder(order: PosOrder, credentials: PosCredentials, customerId: string | null): Promise<string>;

  addLineItems(externalOrderId: string, order: PosOrder, credentials: PosCredentials): Promise<void>;

  triggerFulfillment(externalOrderId: string, credentials: PosCredentials): Promise<{ success: boolean; error?: string }>;
}

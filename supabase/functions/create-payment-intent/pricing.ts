// Pure charge-amount computation, extracted out of index.ts's Deno.serve
// handler so it can be unit tested without a live Supabase/Stripe connection
// (see pricing.test.ts) — security.md §3 Abuse Scenario #1 / supabase-audit.md
// Critical #1: this function must NEVER read a client-supplied amount. It only
// ever derives amountCents from real `menu_items.price` rows the caller
// cannot influence except by choosing which real menu_item_id/quantity pairs
// to order.

export interface OrderItemInput {
  menu_item_id: string;
  quantity: number;
}

export interface MenuItemRow {
  id: string;
  price: number | string;
  truck_id: string;
}

export class MenuItemMismatchError extends Error {
  constructor(menuItemId: string, truckId: string) {
    super(`menu item ${menuItemId} does not belong to truck ${truckId}`);
    this.name = 'MenuItemMismatchError';
  }
}

export function computeOrderAmountCents(
  items: OrderItemInput[],
  menuItems: MenuItemRow[],
  truckId: string,
): number {
  const menuItemById = new Map(menuItems.map((m) => [m.id, m]));
  let amountCents = 0;
  for (const it of items) {
    const menuItem = menuItemById.get(it.menu_item_id);
    if (!menuItem || menuItem.truck_id !== truckId) {
      throw new MenuItemMismatchError(it.menu_item_id, truckId);
    }
    amountCents += Math.round(Number(menuItem.price) * 100) * it.quantity;
  }
  return amountCents;
}

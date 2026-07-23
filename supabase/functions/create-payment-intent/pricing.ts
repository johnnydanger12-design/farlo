// Pure charge-amount computation, extracted out of index.ts's Deno.serve
// handler so it can be unit tested without a live Supabase/Stripe connection
// (see pricing.test.ts) — security.md §3 Abuse Scenario #1 / supabase-audit.md
// Critical #1: this function must NEVER read a client-supplied amount. It only
// ever derives amountCents from real `menu_items.price` (and, for paid add-on
// modifiers, real `menu_item_modifiers.price_delta`) rows the caller cannot
// influence except by choosing which real ids to order.

export interface OrderItemInput {
  menu_item_id: string;
  quantity: number;
  added_modifier_ids?: string[];
  selected_group_option_ids?: string[];
}

export interface MenuItemRow {
  id: string;
  price: number | string;
  truck_id: string;
  category: string;
}

export interface ModifierRow {
  id: string;
  menu_item_id: string;
  price_delta: number | string;
  group_name: string | null;
}

export class MenuItemMismatchError extends Error {
  constructor(menuItemId: string, truckId: string) {
    super(`menu item ${menuItemId} does not belong to truck ${truckId}`);
    this.name = 'MenuItemMismatchError';
  }
}

export class ModifierMismatchError extends Error {
  constructor(modifierId: string, menuItemId: string) {
    super(`modifier ${modifierId} does not belong to menu item ${menuItemId}`);
    this.name = 'ModifierMismatchError';
  }
}

// Thrown when a menu item has one or more required single-select groups
// (modifier rows sharing a non-null group_name) and the client's
// selected_group_option_ids doesn't contain exactly one valid id from every
// such group — either missing entirely or two conflicting picks from the
// same group, both of which would otherwise silently mis-price or
// mis-fulfill the order.
export class RequiredGroupSelectionError extends Error {
  constructor(groupName: string, menuItemId: string) {
    super(`exactly one option is required for group "${groupName}" on menu item ${menuItemId}`);
    this.name = 'RequiredGroupSelectionError';
  }
}

export function computeOrderAmountCents(
  items: OrderItemInput[],
  menuItems: MenuItemRow[],
  modifiers: ModifierRow[],
  truckId: string,
): number {
  const menuItemById = new Map(menuItems.map((m) => [m.id, m]));
  const modifierById = new Map(modifiers.map((m) => [m.id, m]));
  let amountCents = 0;
  for (const it of items) {
    const menuItem = menuItemById.get(it.menu_item_id);
    if (!menuItem || menuItem.truck_id !== truckId) {
      throw new MenuItemMismatchError(it.menu_item_id, truckId);
    }
    let lineCents = Math.round(Number(menuItem.price) * 100);
    for (const modifierId of it.added_modifier_ids ?? []) {
      const modifier = modifierById.get(modifierId);
      if (!modifier || modifier.menu_item_id !== it.menu_item_id) {
        throw new ModifierMismatchError(modifierId, it.menu_item_id);
      }
      lineCents += Math.round(Number(modifier.price_delta) * 100);
    }

    // Required single-select groups: every distinct group_name among this
    // item's real modifiers must have exactly one match in
    // selected_group_option_ids.
    const itemModifiers = modifiers.filter((m) => m.menu_item_id === it.menu_item_id);
    const groupNames = new Set(itemModifiers.filter((m) => m.group_name != null).map((m) => m.group_name!));
    const selectedIds = it.selected_group_option_ids ?? [];
    for (const groupName of groupNames) {
      const groupModifierIds = new Set(itemModifiers.filter((m) => m.group_name === groupName).map((m) => m.id));
      const matches = selectedIds.filter((id) => groupModifierIds.has(id));
      if (matches.length !== 1) {
        throw new RequiredGroupSelectionError(groupName, it.menu_item_id);
      }
      const chosen = modifierById.get(matches[0]);
      if (!chosen || chosen.menu_item_id !== it.menu_item_id) {
        throw new ModifierMismatchError(matches[0], it.menu_item_id);
      }
      lineCents += Math.round(Number(chosen.price_delta) * 100);
    }

    amountCents += lineCents * it.quantity;
  }
  return amountCents;
}

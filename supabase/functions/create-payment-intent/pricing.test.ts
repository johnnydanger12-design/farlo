// security.md §3 Abuse Scenario #1 — "Zero-cost food order via client-
// controlled payment amount": the pre-fix version of create-payment-intent
// read `amount_cents` directly from the client request body. Run with:
//   deno test supabase/functions/create-payment-intent/pricing.test.ts
import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeOrderAmountCents, MenuItemMismatchError } from './pricing.ts';

const menuItems = [
  { id: 'taco', price: 4.5, truck_id: 'truck-1' },
  { id: 'burrito', price: 9.99, truck_id: 'truck-1' },
  { id: 'other-truck-item', price: 1, truck_id: 'truck-2' },
];

Deno.test('computes the correct total from real menu prices, ignoring quantity multiplication rounding per item', () => {
  const cents = computeOrderAmountCents(
    [{ menu_item_id: 'taco', quantity: 2 }, { menu_item_id: 'burrito', quantity: 1 }],
    menuItems,
    'truck-1',
  );
  // 2 * $4.50 + 1 * $9.99 = $18.99
  assertEquals(cents, 1899);
});

Deno.test('ignores any client-supplied amount field smuggled onto the item — the function has no such parameter at all', () => {
  const maliciousItems = [
    { menu_item_id: 'taco', quantity: 1, amount_cents: 1 } as unknown as { menu_item_id: string; quantity: number },
  ];
  const cents = computeOrderAmountCents(maliciousItems, menuItems, 'truck-1');
  // Real price ($4.50 = 450 cents), not the smuggled amount_cents: 1.
  assertEquals(cents, 450);
});

Deno.test('throws if a menu item does not belong to the truck being ordered from (cross-truck price substitution)', () => {
  assertThrows(
    () =>
      computeOrderAmountCents(
        [{ menu_item_id: 'other-truck-item', quantity: 1 }],
        menuItems,
        'truck-1',
      ),
    MenuItemMismatchError,
  );
});

Deno.test('throws if a menu item id does not exist at all', () => {
  assertThrows(
    () => computeOrderAmountCents([{ menu_item_id: 'does-not-exist', quantity: 1 }], menuItems, 'truck-1'),
    MenuItemMismatchError,
  );
});

Deno.test('multiplies price by quantity for every line item', () => {
  const cents = computeOrderAmountCents(
    [{ menu_item_id: 'taco', quantity: 5 }],
    menuItems,
    'truck-1',
  );
  assertEquals(cents, 2250);
});

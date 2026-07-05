// security.md §4 Consolidated Risk Register, Medium — send-employee-invite
// used to send an arbitrary email to anyone with no ownership check at all.
// Run with: deno test supabase/functions/send-employee-invite/authorization.test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { callerOwnsTruck } from './authorization.ts';

Deno.test('rejects a caller who is not the truck owner', () => {
  const truck = { name: 'Truck One', owner_id: 'owner-a' };
  assertEquals(callerOwnsTruck(truck, 'owner-b'), false);
});

Deno.test('rejects when the truck does not exist', () => {
  assertEquals(callerOwnsTruck(null, 'owner-a'), false);
});

Deno.test('accepts the real owner', () => {
  const truck = { name: 'Truck One', owner_id: 'owner-a' };
  assertEquals(callerOwnsTruck(truck, 'owner-a'), true);
});

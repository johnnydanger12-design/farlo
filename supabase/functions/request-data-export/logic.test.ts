import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { hasActiveRequest } from './logic.ts';

Deno.test('hasActiveRequest — no rows means no active request', () => {
  assertEquals(hasActiveRequest([]), false);
});

Deno.test('hasActiveRequest — a pending row counts as active', () => {
  assertEquals(hasActiveRequest([{ status: 'pending' }]), true);
});

Deno.test('hasActiveRequest — a processing row counts as active', () => {
  assertEquals(hasActiveRequest([{ status: 'processing' }]), true);
});

Deno.test('hasActiveRequest — completed/failed/expired rows do not count as active', () => {
  assertEquals(hasActiveRequest([{ status: 'completed' }]), false);
  assertEquals(hasActiveRequest([{ status: 'failed' }]), false);
  assertEquals(hasActiveRequest([{ status: 'expired' }]), false);
});

Deno.test('hasActiveRequest — a mix with one active row still counts as active', () => {
  assertEquals(
    hasActiveRequest([{ status: 'completed' }, { status: 'expired' }, { status: 'pending' }]),
    true,
  );
});

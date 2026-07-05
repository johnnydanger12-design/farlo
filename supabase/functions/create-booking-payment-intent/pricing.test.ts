// security.md §3 Abuse Scenario #1 — "Zero-cost food order via client-
// controlled payment amount", the booking-side equivalent: the pre-fix
// version of create-booking-payment-intent read `amount_cents` directly from
// the client request body, letting anyone mark a real high-value quote/
// deposit "paid" for an arbitrary amount. Run with:
//   deno test supabase/functions/create-booking-payment-intent/pricing.test.ts
import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  AlreadyPaidError,
  computeDepositAmountCents,
  computeInvoiceAmountCents,
  RecordNotFoundError,
} from './pricing.ts';

Deno.test('computeDepositAmountCents: derives the charge from the real stored deposit amount', () => {
  const cents = computeDepositAmountCents(
    { amount: 150.5, booking_id: 'booking-1', status: 'pending' },
    'booking-1',
  );
  assertEquals(cents, 15050);
});

Deno.test('computeDepositAmountCents: throws if the deposit does not belong to the given booking (cross-booking substitution)', () => {
  assertThrows(
    () => computeDepositAmountCents({ amount: 1, booking_id: 'someone-elses-booking', status: 'pending' }, 'booking-1'),
    RecordNotFoundError,
  );
});

Deno.test('computeDepositAmountCents: throws if the deposit does not exist', () => {
  assertThrows(() => computeDepositAmountCents(null, 'booking-1'), RecordNotFoundError);
});

Deno.test('computeDepositAmountCents: throws if the deposit was already paid (no double-charge on a stale client retry)', () => {
  assertThrows(
    () => computeDepositAmountCents({ amount: 100, booking_id: 'booking-1', status: 'paid' }, 'booking-1'),
    AlreadyPaidError,
  );
});

Deno.test('computeInvoiceAmountCents: derives the charge from the real stored quote amount', () => {
  const cents = computeInvoiceAmountCents(
    { amount: 500, booking_id: 'booking-1', status: 'pending', type: 'invoice' },
    'booking-1',
  );
  assertEquals(cents, 50000);
});

Deno.test('computeInvoiceAmountCents: throws if the quote is not actually an invoice-type quote', () => {
  assertThrows(
    () => computeInvoiceAmountCents({ amount: 500, booking_id: 'booking-1', status: 'pending', type: 'estimate' }, 'booking-1'),
    RecordNotFoundError,
  );
});

Deno.test('computeInvoiceAmountCents: throws if the invoice does not belong to the given booking', () => {
  assertThrows(
    () =>
      computeInvoiceAmountCents(
        { amount: 500, booking_id: 'someone-elses-booking', status: 'pending', type: 'invoice' },
        'booking-1',
      ),
    RecordNotFoundError,
  );
});

Deno.test('computeInvoiceAmountCents: throws if the invoice was already paid', () => {
  assertThrows(
    () => computeInvoiceAmountCents({ amount: 500, booking_id: 'booking-1', status: 'paid', type: 'invoice' }, 'booking-1'),
    AlreadyPaidError,
  );
});

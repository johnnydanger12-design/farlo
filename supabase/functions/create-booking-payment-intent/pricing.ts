// Pure charge-amount computation, extracted out of index.ts's Deno.serve
// handler so it can be unit tested without a live Supabase/Stripe connection
// (see pricing.test.ts) — security.md §3 Abuse Scenario #1 / supabase-audit.md
// Critical #1: this function must NEVER read a client-supplied amount. It only
// ever derives amountCents from the real, already-stored `booking_deposits`/
// `booking_quotes` row for the given booking — the caller can only choose
// which real deposit/quote id to pay, never the amount itself.

export type BookingPaymentType = 'deposit' | 'invoice';

export interface BookingDepositRow {
  amount: number | string;
  booking_id: string;
  status: string;
}

export interface BookingQuoteRow {
  amount: number | string;
  booking_id: string;
  status: string;
  type: string;
}

export class RecordNotFoundError extends Error {
  constructor(kind: BookingPaymentType) {
    super(kind === 'deposit' ? 'deposit_not_found' : 'invoice_not_found');
    this.name = 'RecordNotFoundError';
  }
}

export class AlreadyPaidError extends Error {
  constructor(kind: BookingPaymentType) {
    super(kind === 'deposit' ? 'deposit_already_paid' : 'invoice_already_paid');
    this.name = 'AlreadyPaidError';
  }
}

export function computeDepositAmountCents(deposit: BookingDepositRow | null, bookingId: string): number {
  if (!deposit || deposit.booking_id !== bookingId) {
    throw new RecordNotFoundError('deposit');
  }
  if (deposit.status === 'paid') {
    throw new AlreadyPaidError('deposit');
  }
  return Math.round(Number(deposit.amount) * 100);
}

export function computeInvoiceAmountCents(quote: BookingQuoteRow | null, bookingId: string): number {
  if (!quote || quote.booking_id !== bookingId || quote.type !== 'invoice') {
    throw new RecordNotFoundError('invoice');
  }
  if (quote.status === 'paid') {
    throw new AlreadyPaidError('invoice');
  }
  return Math.round(Number(quote.amount) * 100);
}

-- Only one deposit should ever exist per booking. Without this, a resend of a
-- deposit request (owner re-opening "Request Deposit" after the client's stale
-- local cache hid the first one) inserted a second row for the same booking_id.
-- fetchDeposit() uses .maybeSingle(), which throws when 2+ rows come back, and
-- the UI silently swallows that error to `null` — hiding the whole deposit
-- section, including the "Pay Deposit" button, for both owner and customer.
ALTER TABLE "public"."booking_deposits"
  ADD CONSTRAINT "booking_deposits_booking_id_key" UNIQUE ("booking_id");

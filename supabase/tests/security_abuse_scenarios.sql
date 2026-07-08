-- Farlo — permanent regression tests for audit/security.md §3's concrete abuse
-- scenarios (the ones that are RLS/Postgres-function-level, not Edge-Function
-- business logic — see supabase/functions/*/tests for those).
--
-- HOW TO RUN: only ever against an isolated dev/staging branch, never
-- production. See scripts/run_security_abuse_tests.sh, which resolves the
-- branch's connection string via `supabase branches get` and invokes this
-- file with psql. The whole file runs inside one transaction that is always
-- ROLLBACK'd at the end (win or lose), so it never leaves fixture data behind
-- and is safe to re-run repeatedly.
--
-- Each scenario: sets up minimal fixtures, simulates a specific authenticated
-- attacker via `SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claims`
-- (the same mechanism PostgREST itself uses to populate auth.uid()), attempts
-- the abuse, and asserts it now fails. A failed assertion raises an exception,
-- which aborts the whole script with a non-zero exit code — treat any output
-- besides the final "ALL SECURITY ABUSE SCENARIO TESTS PASSED" as a failure.

\set ON_ERROR_STOP on

BEGIN;

-- Run fixture setup and assertions as the table owner so we can freely
-- insert across auth/public/storage regardless of RLS, then switch to
-- `authenticated` + a specific JWT claim to simulate each principal.
RESET ROLE;

-- ── Fixtures ─────────────────────────────────────────────────────────────
DO $fixtures$
DECLARE
  owner_a uuid := '11111111-1111-1111-1111-111111111111';
  owner_b uuid := '22222222-2222-2222-2222-222222222222';
  employee_c uuid := '33333333-3333-3333-3333-333333333333';
  truck1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (owner_a, 'owner-a@test.farlo.internal'),
    (owner_b, 'owner-b@test.farlo.internal'),
    (employee_c, 'employee-c@test.farlo.internal');

  INSERT INTO public.profiles (id, email, display_name, role) VALUES
    (owner_a, 'owner-a@test.farlo.internal', 'Owner A', 'owner'),
    (owner_b, 'owner-b@test.farlo.internal', 'Owner B', 'owner'),
    (employee_c, 'employee-c@test.farlo.internal', 'Employee C', 'consumer');

  INSERT INTO public.food_trucks (id, owner_id, name, cuisine_type, is_active)
  VALUES (truck1, owner_a, 'Truck One', 'Tacos', true);

  -- owner_b placed a real, still-unpaid order at Truck One (scenario 9) —
  -- deliberately NOT employee_c, whose auth.users row scenario 5 deletes for
  -- real later in this same script; orders.consumer_id cascades on delete,
  -- which would silently remove this fixture before scenario 9 runs.
  INSERT INTO public.orders (id, truck_id, consumer_id, status, payment_status, total_price) VALUES
    ('66666666-6666-6666-6666-666666666666', truck1, owner_b, 'pending', 'unpaid', 12.50);

  -- Employee C is a legitimate, already-active employee of Truck One
  -- (scenario 4 needs a real employee whose own row this is, not an
  -- attacker escalating privilege — that's scenario 3).
  INSERT INTO public.truck_employees (truck_id, invited_email, user_id, status, linked_at)
  VALUES (truck1, 'employee-c@test.farlo.internal', employee_c, 'active', now());
END;
$fixtures$;

-- ── Scenario 3: employee-invite ownership escalation ────────────────────
-- security.md §3 Abuse Scenario #3 — an attacker calls
-- invite_employee_by_email against a truck they don't own, instantly
-- becoming an active employee with zero approval.
DO $scenario3$
BEGIN
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  BEGIN
    PERFORM public.invite_employee_by_email('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'attacker@test.farlo.internal');
    RAISE EXCEPTION 'SCENARIO 3 FAILED: owner_b was able to invite themselves as an employee of truck1, which they do not own';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 3 PASSED: non-owner invite correctly rejected (%)', SQLERRM;
  END;
END;
$scenario3$;

-- ── Scenario 4: timesheet fraud via fabricated clock times ──────────────
-- security.md §3 Abuse Scenario #4 — a legitimate employee PATCHes their own
-- employee_shifts row directly via the REST API with a backdated
-- clocked_in_at, or rewrites clocked_out_at on an already-closed shift.
DO $scenario4$
DECLARE
  shift_id uuid;
BEGIN
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

  -- A real, honest clock-in must still succeed (this is not a check for
  -- "nothing can ever be inserted" — only that fabricated timestamps are
  -- rejected).
  INSERT INTO public.employee_shifts (id, truck_id, employee_id, clocked_in_at)
  VALUES (gen_random_uuid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', now())
  RETURNING id INTO shift_id;

  -- Fabricated backdated clock-in (fraud: claiming hours never worked) must
  -- now be rejected by employee_shifts_insert_own's WITH CHECK.
  BEGIN
    INSERT INTO public.employee_shifts (id, truck_id, employee_id, clocked_in_at)
    VALUES (gen_random_uuid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', now() - interval '2 days');
    RAISE EXCEPTION 'SCENARIO 4a FAILED: employee inserted a shift with a fabricated 2-day-old clock-in time';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE IN ('42501', '23514') THEN
        RAISE NOTICE 'Scenario 4a PASSED: backdated clock-in correctly rejected (%)', SQLERRM;
      ELSE
        RAISE;
      END IF;
  END;

  -- Fabricated far-future clock-out on the real shift (fraud: inflating
  -- hours worked) must also be rejected.
  BEGIN
    UPDATE public.employee_shifts
    SET clocked_out_at = now() + interval '3 days'
    WHERE id = shift_id;
    RAISE EXCEPTION 'SCENARIO 4b FAILED: employee set a fabricated far-future clock-out time on their own shift';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN
        RAISE NOTICE 'Scenario 4b PASSED: fabricated clock-out correctly rejected (%)', SQLERRM;
      ELSE
        RAISE;
      END IF;
  END;
END;
$scenario4$;

-- ── Scenario 5: half-deleted "zombie" account ────────────────────────────
-- security.md §3 Abuse Scenario #5 — a consumer who once sent a message in
-- someone else's booking chat could not be deleted at all: the final
-- auth.users delete threw a foreign-key violation on booking_messages, and
-- was left half-deleted. delete_account_data() must clear every blocker.
DO $scenario5$
DECLARE
  booking_id uuid;
BEGIN
  RESET ROLE;
  INSERT INTO public.event_booking_requests
    (id, truck_id, requester_id, contact_name, contact_email, event_date, event_time, event_location)
  VALUES
    (gen_random_uuid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
     'Owner A', 'owner-a@test.farlo.internal', current_date + 7, '18:00', 'Main St')
  RETURNING id INTO booking_id;

  -- Employee C sent a message into a booking thread that belongs to a truck
  -- other than their own (the realistic case per the original red/green
  -- session's own correction) — this is exactly the row shape that used to
  -- block account deletion.
  INSERT INTO public.booking_messages (id, booking_id, sender_id, body)
  VALUES (gen_random_uuid(), booking_id, '33333333-3333-3333-3333-333333333333', 'Looking forward to it!');

  -- Old behavior (pre-fix): calling auth.users delete directly at this point
  -- would throw booking_messages_sender_id_fkey. Confirm that's still true of
  -- the raw FK (i.e. this fixture genuinely reproduces the trap) before
  -- trusting the fix's own cleanup step. A nested BEGIN/EXCEPTION block in
  -- PL/pgSQL runs against an implicit savepoint that's automatically rolled
  -- back when the exception is caught — no explicit SAVEPOINT needed (and
  -- explicit SAVEPOINT/ROLLBACK TO isn't valid inside a PL/pgSQL body anyway).
  BEGIN
    DELETE FROM auth.users WHERE id = '33333333-3333-3333-3333-333333333333';
    RAISE EXCEPTION 'SCENARIO 5 SETUP INVALID: raw auth.users delete succeeded without delete_account_data() — fixture no longer reproduces the original FK-violation trap, re-derive it';
  EXCEPTION
    WHEN foreign_key_violation THEN
      RAISE NOTICE 'Scenario 5 setup confirmed: raw delete still hits booking_messages_sender_id_fkey as expected';
  END;

  -- Now run the actual fix and confirm the subsequent auth.users delete
  -- succeeds cleanly.
  PERFORM public.delete_account_data('33333333-3333-3333-3333-333333333333');
  DELETE FROM auth.users WHERE id = '33333333-3333-3333-3333-333333333333';
  RAISE NOTICE 'Scenario 5 PASSED: delete_account_data() cleared the blocker, auth.users delete succeeded cleanly';
END;
$scenario5$;

-- ── Scenario 6: cross-tenant menu-photo defacement ──────────────────────
-- security.md §3 Abuse Scenario #6 — any authenticated user could
-- overwrite/delete another truck's menu photos by calling the Storage API
-- directly, bypassing the app's own "safe" path construction.
DO $scenario6$
BEGIN
  RESET ROLE;
  INSERT INTO storage.objects (id, bucket_id, name, owner)
  VALUES (gen_random_uuid(), 'menu-item-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/original-menu.jpg', '11111111-1111-1111-1111-111111111111');

  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  -- owner_b (unrelated to truck1) uploading into truck1's photo folder.
  BEGIN
    INSERT INTO storage.objects (id, bucket_id, name, owner)
    VALUES (gen_random_uuid(), 'menu-item-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/attack.jpg', '22222222-2222-2222-2222-222222222222');
    RAISE EXCEPTION 'SCENARIO 6a FAILED: owner_b uploaded into truck1''s menu-photo folder despite not owning truck1';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 6a PASSED: cross-tenant upload correctly rejected (%)', SQLERRM;
  END;

  -- owner_b deleting truck1's real, legitimate menu photo.
  BEGIN
    DELETE FROM storage.objects
    WHERE bucket_id = 'menu-item-photos' AND name = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/original-menu.jpg';
    IF FOUND THEN
      RAISE EXCEPTION 'SCENARIO 6b FAILED: owner_b deleted truck1''s legitimate menu photo despite not owning truck1';
    END IF;
    RAISE NOTICE 'Scenario 6b PASSED: cross-tenant delete affected zero rows (RLS filtered it out)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 6b PASSED: cross-tenant delete correctly rejected (%)', SQLERRM;
  END;
END;
$scenario6$;

-- ── Scenario 9: fraudulent payment_status flip (Medium finding, security.md
-- Consolidated Risk Register) — an owner/employee marking their own order
-- "paid" via a raw UPDATE with no real Stripe charge behind it.
DO $scenario9$
BEGIN
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  BEGIN
    UPDATE public.orders SET payment_status = 'paid' WHERE id = '66666666-6666-6666-6666-666666666666';
    RAISE EXCEPTION 'SCENARIO 9a FAILED: owner_a flipped payment_status to paid with no real charge';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 9a PASSED: direct payment_status change correctly rejected (%)', SQLERRM;
  END;

  -- Legitimate, non-payment status transitions must still work for the owner.
  UPDATE public.orders SET status = 'accepted' WHERE id = '66666666-6666-6666-6666-666666666666';
  RAISE NOTICE 'Scenario 9b PASSED: owner can still update order status normally';

  RESET ROLE;
  -- The real payment path (service_role, e.g. the Stripe webhook) must still work.
  SET LOCAL ROLE service_role;
  SET LOCAL request.jwt.claims = '{"role":"service_role"}';
  UPDATE public.orders SET payment_status = 'paid' WHERE id = '66666666-6666-6666-6666-666666666666';
  IF (SELECT payment_status FROM public.orders WHERE id = '66666666-6666-6666-6666-666666666666') = 'paid' THEN
    RAISE NOTICE 'Scenario 9c PASSED: service_role (Stripe webhook) payment path still works';
  ELSE
    RAISE EXCEPTION 'SCENARIO 9c FAILED: service_role could not mark a real payment as paid';
  END IF;
END;
$scenario9$;

-- ── Scenario 10: GDPR data-export cross-tenant leakage (ARCH item, not
-- numbered in the original audit — added when compile_user_data_export()
-- was built) — a business owner's data export must include only their own
-- account and their own truck's operational data (which they already see
-- via the app's normal Order Queue/Booking Requests screens), and must
-- never include another user's profile/account data.
DO $scenario10$
DECLARE
  export_a jsonb;
  export_b jsonb;
BEGIN
  RESET ROLE;
  export_a := public.compile_user_data_export('11111111-1111-1111-1111-111111111111');
  export_b := public.compile_user_data_export('22222222-2222-2222-2222-222222222222');

  IF export_a->'owned_truck'->'truck'->>'name' != 'Truck One' THEN
    RAISE EXCEPTION 'SCENARIO 10a FAILED: owner_a export missing their own truck';
  END IF;
  IF NOT (export_a->'owned_truck'->'orders_received' @> jsonb_build_array(jsonb_build_object('id', '66666666-6666-6666-6666-666666666666'))) THEN
    RAISE EXCEPTION 'SCENARIO 10b FAILED: owner_a export missing an order legitimately placed at their own truck';
  END IF;
  IF export_a->'profile'->>'email' != 'owner-a@test.farlo.internal' THEN
    RAISE EXCEPTION 'SCENARIO 10c FAILED: owner_a export profile is not their own';
  END IF;

  -- jsonb_build_object always includes the 'owned_truck' key, so a "no
  -- truck" result is the JSON literal null (jsonb_typeof = 'null'), not the
  -- key being absent (which is what a plain `IS NOT NULL` check on the ->
  -- result would need — jsonb 'null'::jsonb IS NOT NULL is true in Postgres,
  -- since it's a defined value, just one representing JSON null).
  IF jsonb_typeof(export_b->'owned_truck') IS DISTINCT FROM 'null' THEN
    RAISE EXCEPTION 'SCENARIO 10d FAILED: owner_b (who owns no truck) export attributes a truck to them — cross-tenant leak of owner_a''s business';
  END IF;
  IF export_b->'profile'->>'email' != 'owner-b@test.farlo.internal' THEN
    RAISE EXCEPTION 'SCENARIO 10e FAILED: owner_b export profile is not their own';
  END IF;

  RAISE NOTICE 'Scenario 10a-e PASSED: compile_user_data_export() is correctly scoped per-caller, no cross-tenant leakage';
END;
$scenario10$;

-- ── Scenario 11: data_export_requests RLS ───────────────────────────────
-- A user must never see or be able to forge another user's export request
-- row (which, once completed, carries a live signed download URL to that
-- user's full data export).
DO $scenario11$
DECLARE
  visible_count int;
BEGIN
  RESET ROLE;
  INSERT INTO public.data_export_requests (id, user_id, status)
  VALUES ('77777777-7777-7777-7777-777777777777', '11111111-1111-1111-1111-111111111111', 'completed');

  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  SELECT count(*) INTO visible_count FROM public.data_export_requests WHERE id = '77777777-7777-7777-7777-777777777777';
  IF visible_count != 0 THEN
    RAISE EXCEPTION 'SCENARIO 11a FAILED: owner_b could see owner_a''s data export request (and its signed download URL)';
  END IF;
  RAISE NOTICE 'Scenario 11a PASSED: export request row correctly invisible to a different user';

  BEGIN
    INSERT INTO public.data_export_requests (user_id, status) VALUES ('11111111-1111-1111-1111-111111111111', 'pending');
    RAISE EXCEPTION 'SCENARIO 11b FAILED: an authenticated client was able to directly insert an export request row (should only ever happen via the service-role Edge Function)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 11b PASSED: direct client insert correctly rejected (%)', SQLERRM;
  END;

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  SELECT count(*) INTO visible_count FROM public.data_export_requests WHERE id = '77777777-7777-7777-7777-777777777777';
  IF visible_count != 1 THEN
    RAISE EXCEPTION 'SCENARIO 11c FAILED: owner_a could not see their own completed export request';
  END IF;
  RAISE NOTICE 'Scenario 11c PASSED: export request row correctly visible to its own owner';
END;
$scenario11$;

-- ── Scenario 12: internal-only SECURITY DEFINER functions must not be
-- directly callable by anon/authenticated — found by this iteration's
-- required full non-sampled re-verification pass (get_advisors flagged both
-- as executable by anon/authenticated; live-confirmed exploitable via a real
-- unauthenticated HTTP request before the fix — see REMEDIATION_LOG.md).
-- Neither function checks the caller's identity against p_user_id
-- internally; they're only meant to be invoked by their Edge Functions using
-- the service role key.
DO $scenario12$
BEGIN
  RESET ROLE;

  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.compile_user_data_export('11111111-1111-1111-1111-111111111111');
    RAISE EXCEPTION 'SCENARIO 12a FAILED: anon (fully unauthenticated) was able to call compile_user_data_export directly and exfiltrate another user''s full data export';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 12a PASSED: anon correctly denied EXECUTE on compile_user_data_export (%)', SQLERRM;
  END;

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  BEGIN
    PERFORM public.compile_user_data_export('11111111-1111-1111-1111-111111111111');
    RAISE EXCEPTION 'SCENARIO 12b FAILED: owner_b was able to call compile_user_data_export directly for owner_a''s account';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 12b PASSED: authenticated correctly denied EXECUTE on compile_user_data_export (%)', SQLERRM;
  END;

  RESET ROLE;
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.delete_account_data('11111111-1111-1111-1111-111111111111');
    RAISE EXCEPTION 'SCENARIO 12c FAILED: anon (fully unauthenticated) was able to call delete_account_data directly against another user''s account';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 12c PASSED: anon correctly denied EXECUTE on delete_account_data (%)', SQLERRM;
  END;

  RESET ROLE;
  -- The real path (service_role, from delete-account/process-data-exports'
  -- Edge Functions) must still work.
  SET LOCAL ROLE service_role;
  PERFORM public.compile_user_data_export('11111111-1111-1111-1111-111111111111');
  RAISE NOTICE 'Scenario 12d PASSED: service_role can still call compile_user_data_export (the real Edge Function path)';
END;
$scenario12$;

-- ── Scenario 13: founder dashboard access (is_founder()) ────────────────
-- Added when supabase/migrations/20260707015823_add_founder_dashboard_access.sql
-- opened read access to the agent fleet + all-rows business metrics for the
-- founder dashboard (dash.farlo.app). is_founder() is an email check, not a
-- hardcoded auth.uid(), so a fixture user with the real founder email is
-- required to exercise the true/false branches of every new policy.
DO $scenario13$
DECLARE
  founder uuid := '99999999-9999-9999-9999-999999999999';
  truck2 uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  test_run_id uuid;
  n int;
BEGIN
  RESET ROLE;

  INSERT INTO auth.users (id, email) VALUES (founder, 'johnny@farlo.app');
  INSERT INTO public.profiles (id, email, display_name, role)
  VALUES (founder, 'johnny@farlo.app', 'Founder', 'consumer');

  -- owner_b's second truck, inactive — invisible to the public "is_active"
  -- policy and to anyone who isn't its owner, so it's a real test of the new
  -- founder all-rows policy rather than something already publicly readable.
  INSERT INTO public.food_trucks (id, owner_id, name, cuisine_type, is_active)
  VALUES (truck2, '22222222-2222-2222-2222-222222222222', 'Truck Two (inactive)', 'BBQ', false);

  INSERT INTO public.subscriptions (owner_id, status, product_identifier)
  VALUES ('22222222-2222-2222-2222-222222222222', 'active', 'owner_monthly');

  INSERT INTO public.agent_run_log (id, agent_name, status, summary)
  VALUES (gen_random_uuid(), 'aiden', 'success', 'test run') RETURNING id INTO test_run_id;
  INSERT INTO public.agent_tool_call_log (run_id, sequence, tool_name)
  VALUES (test_run_id, 1, 'update_directive');
  INSERT INTO public.sales_prospects (business_name) VALUES ('Test Prospect Co');
  INSERT INTO public.supervisor_reports (week_of, report_content)
  VALUES (current_date, 'weekly report body');
  INSERT INTO public.content_queue (platform, caption) VALUES ('instagram', 'test caption');
  INSERT INTO public.support_tickets (from_email, subject, body)
  VALUES ('someone@test.farlo.internal', 'Help', 'test ticket body');

  INSERT INTO public.agent_directives (directive_key, content, locked) VALUES
    ('test_unlocked_directive', 'editable content', false),
    ('test_locked_directive', 'protected content', true);

  -- ── Founder: every newly-opened table must be readable ──────────────────
  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', founder, 'email', 'johnny@farlo.app', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM public.agent_run_log WHERE id = test_run_id;
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13a FAILED: founder could not read agent_run_log'; END IF;

  SELECT count(*) INTO n FROM public.agent_tool_call_log WHERE run_id = test_run_id;
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13b FAILED: founder could not read agent_tool_call_log'; END IF;

  SELECT count(*) INTO n FROM public.sales_prospects WHERE business_name = 'Test Prospect Co';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13c FAILED: founder could not read sales_prospects'; END IF;

  SELECT count(*) INTO n FROM public.supervisor_reports WHERE report_content = 'weekly report body';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13d FAILED: founder could not read supervisor_reports'; END IF;

  SELECT count(*) INTO n FROM public.content_queue WHERE caption = 'test caption';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13e FAILED: founder could not read content_queue'; END IF;

  SELECT count(*) INTO n FROM public.support_tickets WHERE subject = 'Help';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13f FAILED: founder could not read support_tickets'; END IF;

  SELECT count(*) INTO n FROM public.food_trucks WHERE id = truck2;
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13g FAILED: founder could not read an inactive truck they do not own'; END IF;

  SELECT count(*) INTO n FROM public.subscriptions WHERE owner_id = '22222222-2222-2222-2222-222222222222';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13h FAILED: founder could not read another owner''s subscription'; END IF;

  -- owner_a and owner_b are neither the founder nor an employer/employee of
  -- the founder — the only thing that could make them visible is the new
  -- all-rows policy. (employee_c is deliberately not checked here: scenario
  -- 5, earlier in this same transaction, really deletes that auth.users row.)
  SELECT count(*) INTO n FROM public.profiles WHERE id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');
  IF n != 2 THEN RAISE EXCEPTION 'SCENARIO 13i FAILED: founder profiles read did not return all rows (got % of 2 expected)', n; END IF;

  RAISE NOTICE 'Scenario 13a-i PASSED: founder can read every newly-opened table';

  -- Founder UPDATE on an unlocked directive succeeds.
  UPDATE public.agent_directives SET content = 'edited by founder' WHERE directive_key = 'test_unlocked_directive';
  SELECT count(*) INTO n FROM public.agent_directives WHERE directive_key = 'test_unlocked_directive' AND content = 'edited by founder';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13j FAILED: founder could not update an unlocked directive'; END IF;
  RAISE NOTICE 'Scenario 13j PASSED: founder can edit an unlocked directive';

  -- Founder UPDATE on a locked directive must affect zero rows.
  UPDATE public.agent_directives SET content = 'should not stick' WHERE directive_key = 'test_locked_directive';
  SELECT count(*) INTO n FROM public.agent_directives WHERE directive_key = 'test_locked_directive' AND content = 'should not stick';
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13k FAILED: founder was able to edit a locked directive'; END IF;
  RAISE NOTICE 'Scenario 13k PASSED: founder cannot edit a locked directive';

  -- ── Non-founder (owner_b, a real but different authenticated user):
  -- every newly-opened table must return zero rows, and directive edits
  -- must be blocked entirely.
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', '22222222-2222-2222-2222-222222222222', 'email', 'owner-b@test.farlo.internal', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM public.agent_run_log;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13l FAILED: non-founder could read agent_run_log'; END IF;

  SELECT count(*) INTO n FROM public.agent_tool_call_log;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13m FAILED: non-founder could read agent_tool_call_log'; END IF;

  SELECT count(*) INTO n FROM public.sales_prospects;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13n FAILED: non-founder could read sales_prospects'; END IF;

  SELECT count(*) INTO n FROM public.supervisor_reports;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13o FAILED: non-founder could read supervisor_reports'; END IF;

  SELECT count(*) INTO n FROM public.content_queue;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13p FAILED: non-founder could read content_queue'; END IF;

  SELECT count(*) INTO n FROM public.support_tickets;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13q FAILED: non-founder could read support_tickets'; END IF;

  SELECT count(*) INTO n FROM public.agent_directives;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13r FAILED: non-founder could read agent_directives'; END IF;

  -- owner_b legitimately still sees only their own truck (their own row
  -- policy), not the founder's all-rows visibility into others'.
  SELECT count(*) INTO n FROM public.food_trucks WHERE owner_id != '22222222-2222-2222-2222-222222222222' AND is_active = false;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13s FAILED: non-founder could read another owner''s inactive truck'; END IF;

  SELECT count(*) INTO n FROM public.profiles;
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 13t FAILED: non-founder profiles read was not scoped to their own row (got %)', n; END IF;

  UPDATE public.agent_directives SET content = 'attacker edit' WHERE directive_key = 'test_unlocked_directive';
  SELECT count(*) INTO n FROM public.agent_directives WHERE directive_key = 'test_unlocked_directive' AND content = 'attacker edit';
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 13u FAILED: non-founder was able to edit an unlocked directive'; END IF;

  RAISE NOTICE 'Scenario 13l-u PASSED: non-founder is correctly denied read/write on every founder-only table and directive edits';
END;
$scenario13$;

-- ── Scenario 14: agent_cron_call() reachable by anon/authenticated ──────
-- Found while building the founder dashboard's "Run now" button — the original
-- baseline migration granted EXECUTE on agent_cron_call(fn_name, dry_run) to
-- anon and authenticated (and left the default PUBLIC grant in place), meaning
-- any fully unauthenticated caller with only the public anon key could invoke
-- a real, non-dry-run agent run directly via PostgREST RPC. Fixed in
-- 20260707021420_lock_down_agent_cron_call.sql +
-- 20260707021505_revoke_agent_cron_call_public_grant.sql. The dashboard's
-- "Run now" button instead calls founder_trigger_agent(fn_name), a
-- SECURITY DEFINER wrapper gated by is_founder().
DO $scenario14$
BEGIN
  RESET ROLE;

  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.agent_cron_call('agent-sage', false);
    RAISE EXCEPTION 'SCENARIO 14a FAILED: anon (fully unauthenticated) was able to call agent_cron_call directly and trigger a real agent run';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 14a PASSED: anon correctly denied EXECUTE on agent_cron_call (%)', SQLERRM;
  END;

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","email":"owner-b@test.farlo.internal","role":"authenticated"}';
  BEGIN
    PERFORM public.agent_cron_call('agent-sage', false);
    RAISE EXCEPTION 'SCENARIO 14b FAILED: a regular authenticated user was able to call agent_cron_call directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 14b PASSED: regular authenticated user correctly denied EXECUTE on agent_cron_call (%)', SQLERRM;
  END;

  -- A regular authenticated user must also be denied the founder-only wrapper.
  BEGIN
    PERFORM public.founder_trigger_agent('agent-sage');
    RAISE EXCEPTION 'SCENARIO 14c FAILED: a regular authenticated user was able to call founder_trigger_agent';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 14c PASSED: non-founder correctly denied by founder_trigger_agent (%)', SQLERRM;
  END;

  RESET ROLE;
  -- The real path (pg_cron, running as postgres/service_role) must still work.
  SET LOCAL ROLE service_role;
  PERFORM public.agent_cron_call('dashboard-verification-noop-test', true);
  RAISE NOTICE 'Scenario 14d PASSED: service_role (the real pg_cron path) can still call agent_cron_call';
END;
$scenario14$;

-- ── Scenario 15: founder UPDATE on content_queue and sales_prospects ─────
-- Added alongside the dashboard's new Content and Outreach tabs, which let the founder
-- mark content_queue items posted/skipped and flip a drafted sales_prospects row to
-- 'contacted' once actually sent. Both were previously service-role-only for writes.
DO $scenario15$
DECLARE
  founder uuid := '99999999-9999-9999-9999-999999999999';
  content_id uuid;
  prospect_id uuid;
  n int;
BEGIN
  RESET ROLE;

  -- founder row already inserted by Scenario 13's fixtures earlier in this same
  -- transaction; re-insert defensively in case scenario ordering ever changes.
  INSERT INTO auth.users (id, email) VALUES (founder, 'johnny@farlo.app')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (id, email, display_name, role)
    VALUES (founder, 'johnny@farlo.app', 'Founder', 'consumer')
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.content_queue (platform, caption, status)
    VALUES ('instagram', 'scenario 15 test caption', 'queued') RETURNING id INTO content_id;
  INSERT INTO public.sales_prospects (business_name, status)
    VALUES ('Scenario 15 Test Business', 'drafted') RETURNING id INTO prospect_id;

  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', founder, 'email', 'johnny@farlo.app', 'role', 'authenticated')::text);

  UPDATE public.content_queue SET status = 'posted' WHERE id = content_id;
  SELECT count(*) INTO n FROM public.content_queue WHERE id = content_id AND status = 'posted';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 15a FAILED: founder could not mark content_queue posted'; END IF;

  UPDATE public.sales_prospects SET status = 'contacted', last_contacted_at = now() WHERE id = prospect_id;
  SELECT count(*) INTO n FROM public.sales_prospects WHERE id = prospect_id AND status = 'contacted';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 15b FAILED: founder could not mark sales_prospects contacted'; END IF;

  RAISE NOTICE 'Scenario 15a-b PASSED: founder can update content_queue and sales_prospects';

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', '22222222-2222-2222-2222-222222222222', 'email', 'owner-b@test.farlo.internal', 'role', 'authenticated')::text);

  UPDATE public.content_queue SET status = 'skipped' WHERE id = content_id;
  SELECT count(*) INTO n FROM public.content_queue WHERE id = content_id AND status = 'skipped';
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 15c FAILED: non-founder was able to update content_queue'; END IF;

  UPDATE public.sales_prospects SET status = 'not_interested' WHERE id = prospect_id;
  SELECT count(*) INTO n FROM public.sales_prospects WHERE id = prospect_id AND status = 'not_interested';
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 15d FAILED: non-founder was able to update sales_prospects'; END IF;

  RAISE NOTICE 'Scenario 15c-d PASSED: non-founder correctly denied on both tables';
END;
$scenario15$;

-- ── Scenario 16: aiden_chat_messages — founder read-only, no client writes ──
-- Added alongside the dashboard's live Aiden chat. Writes to this table only ever
-- happen server-side (aiden-chat Edge Function, service_role) — even the founder must
-- not be able to insert/forge a message directly, since the "founder" role in a chat
-- message's provenance should only ever mean "actually went through the Anthropic call
-- and got logged", not "any authenticated client claiming to be founder wrote a row".
DO $scenario16$
DECLARE
  founder uuid := '99999999-9999-9999-9999-999999999999';
  conv_id uuid;
  n int;
BEGIN
  RESET ROLE;
  INSERT INTO auth.users (id, email) VALUES (founder, 'johnny@farlo.app')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (id, email, display_name, role)
    VALUES (founder, 'johnny@farlo.app', 'Founder', 'consumer')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.aiden_conversations (title) VALUES ('seed conversation for scenario 16')
    RETURNING id INTO conv_id;
  INSERT INTO public.aiden_chat_messages (conversation_id, role, content) VALUES (conv_id, 'founder', 'seed message for scenario 16');

  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', founder, 'email', 'johnny@farlo.app', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM public.aiden_chat_messages WHERE conversation_id = conv_id;
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 16a FAILED: founder could not read aiden_chat_messages (got %)', n; END IF;
  RAISE NOTICE 'Scenario 16a PASSED: founder can read aiden_chat_messages';

  BEGIN
    INSERT INTO public.aiden_chat_messages (conversation_id, role, content) VALUES (conv_id, 'founder', 'direct client insert attempt');
    RAISE EXCEPTION 'SCENARIO 16b FAILED: founder was able to insert into aiden_chat_messages directly (bypassing the Edge Function)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 16b PASSED: direct founder insert correctly rejected (%)', SQLERRM;
  END;

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', '22222222-2222-2222-2222-222222222222', 'email', 'owner-b@test.farlo.internal', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM public.aiden_chat_messages;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 16c FAILED: non-founder could read aiden_chat_messages'; END IF;
  RAISE NOTICE 'Scenario 16c PASSED: non-founder correctly denied read on aiden_chat_messages';
END;
$scenario16$;

-- ── Scenario 17: aiden_conversations — founder read-only, no client writes ──
-- Same shape as Scenario 16, added when aiden_chat_messages grew a conversation_id
-- FK to support Recents/New Chat — conversation rows carry the same provenance
-- requirement as messages: only the aiden-chat Edge Function (service_role) may
-- create/touch them.
DO $scenario17$
DECLARE
  founder uuid := '99999999-9999-9999-9999-999999999999';
  conv_id uuid;
  n int;
BEGIN
  RESET ROLE;
  INSERT INTO auth.users (id, email) VALUES (founder, 'johnny@farlo.app')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (id, email, display_name, role)
    VALUES (founder, 'johnny@farlo.app', 'Founder', 'consumer')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.aiden_conversations (title) VALUES ('seed conversation for scenario 17')
    RETURNING id INTO conv_id;

  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', founder, 'email', 'johnny@farlo.app', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM public.aiden_conversations WHERE id = conv_id;
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 17a FAILED: founder could not read aiden_conversations (got %)', n; END IF;
  RAISE NOTICE 'Scenario 17a PASSED: founder can read aiden_conversations';

  BEGIN
    INSERT INTO public.aiden_conversations (title) VALUES ('direct client insert attempt');
    RAISE EXCEPTION 'SCENARIO 17b FAILED: founder was able to insert into aiden_conversations directly (bypassing the Edge Function)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 17b PASSED: direct founder insert correctly rejected (%)', SQLERRM;
  END;

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', '22222222-2222-2222-2222-222222222222', 'email', 'owner-b@test.farlo.internal', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM public.aiden_conversations WHERE id = conv_id;
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 17c FAILED: non-founder could read aiden_conversations'; END IF;
  RAISE NOTICE 'Scenario 17c PASSED: non-founder correctly denied read on aiden_conversations';
END;
$scenario17$;

-- ── Scenario 18: aiden-chat-photos storage bucket — founder only ───────────
-- Unlike every other bucket in this project (public=true, per-user-folder RLS),
-- this bucket is founder-only and private — verify a non-founder gets nothing
-- (SELECT) and can't write (INSERT), even though they're an authenticated user
-- and every other bucket's convention would otherwise let *some* authenticated
-- writes through.
DO $scenario18$
DECLARE
  founder uuid := '99999999-9999-9999-9999-999999999999';
  n int;
BEGIN
  RESET ROLE;
  INSERT INTO storage.objects (id, bucket_id, name, owner)
  VALUES (gen_random_uuid(), 'aiden-chat-photos', 'chat/seed-scenario-18.jpg', founder);

  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', founder, 'email', 'johnny@farlo.app', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'aiden-chat-photos' AND name = 'chat/seed-scenario-18.jpg';
  IF n != 1 THEN RAISE EXCEPTION 'SCENARIO 18a FAILED: founder could not read aiden-chat-photos'; END IF;
  RAISE NOTICE 'Scenario 18a PASSED: founder can read aiden-chat-photos';

  RESET ROLE;
  SET LOCAL ROLE authenticated;
  EXECUTE format('SET LOCAL request.jwt.claims = %L', jsonb_build_object('sub', '22222222-2222-2222-2222-222222222222', 'email', 'owner-b@test.farlo.internal', 'role', 'authenticated')::text);

  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'aiden-chat-photos';
  IF n != 0 THEN RAISE EXCEPTION 'SCENARIO 18b FAILED: non-founder could read aiden-chat-photos'; END IF;
  RAISE NOTICE 'Scenario 18b PASSED: non-founder correctly denied read on aiden-chat-photos';

  BEGIN
    INSERT INTO storage.objects (id, bucket_id, name, owner)
    VALUES (gen_random_uuid(), 'aiden-chat-photos', 'chat/attack.jpg', '22222222-2222-2222-2222-222222222222');
    RAISE EXCEPTION 'SCENARIO 18c FAILED: non-founder was able to upload into aiden-chat-photos';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Scenario 18c PASSED: non-founder upload correctly rejected (%)', SQLERRM;
  END;
END;
$scenario18$;

RESET ROLE;
DO $$ BEGIN RAISE NOTICE 'ALL SECURITY ABUSE SCENARIO TESTS PASSED'; END $$;

ROLLBACK;

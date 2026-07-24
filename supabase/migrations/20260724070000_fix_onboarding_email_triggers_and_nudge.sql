-- Two real, since-baseline bugs found 2026-07-24 while investigating why
-- stalled owner signups never got their onboarding emails: both
-- trigger_send_owner_onboarding_emails() and trigger_send_consumer_welcome_email()
-- called "extensions.http_post", which does not exist in this project (only
-- "net.http_post" does, via the pg_net extension — every other trigger in
-- this codebase already uses net.http_post correctly). Each WHEN OTHERS
-- exception handler silently swallowed the resulting error AND rolled back
-- the function's own earlier "mark sent" UPDATE (Postgres implicit-savepoint
-- behavior for a PL/pgSQL EXCEPTION block), so this has been a 100%,
-- invisible failure for every owner signup and every consumer signup since
-- this table was created — confirmed via onboarding_emails_sent_at being
-- NULL for all 5 real Hartsville business signups to date.

CREATE OR REPLACE FUNCTION "public"."trigger_send_owner_onboarding_emails"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Mark sent first to block any recursive UPDATE from re-triggering
  UPDATE public.subscriptions
    SET onboarding_emails_sent_at = NOW()
    WHERE id = NEW.id;

  PERFORM net.http_post(
    url := 'https://weflrxyerxpsafcdetya.supabase.co/functions/v1/send-owner-onboarding-emails',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := jsonb_build_object(
      'owner_id', NEW.owner_id::text,
      'subscription_id', NEW.id::text
    )
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Onboarding email trigger failed: %', SQLERRM;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."trigger_send_consumer_welcome_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  PERFORM net.http_post(
    url := 'https://weflrxyerxpsafcdetya.supabase.co/functions/v1/send-consumer-welcome-email',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := jsonb_build_object('user_id', NEW.id::text)
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Consumer welcome email trigger failed: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- Idempotency stamp for the new push-notification onboarding nudge (separate
-- from subscriptions.onboarding_emails_sent_at, which is the email drip).
ALTER TABLE public.food_trucks ADD COLUMN IF NOT EXISTS onboarding_nudge_sent_at timestamp with time zone;




SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean DEFAULT true) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  bearer text;
begin
  -- 1-2 min jitter so scheduled runs don't all fire at the exact same second
  perform pg_sleep(floor(random() * 90));

  select decrypted_secret into bearer from vault.decrypted_secrets where name = 'agent_cron_bearer';

  perform net.http_post(
    url := 'https://weflrxyerxpsafcdetya.supabase.co/functions/v1/' || fn_name
           || case when dry_run then '?dry_run=true' else '' end,
    headers := jsonb_build_object('Authorization', 'Bearer ' || bearer, 'Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
end;
$$;


ALTER FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auth_user_in_booking"("p_booking_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   event_booking_requests ebr
    JOIN   food_trucks ft ON ft.id = ebr.truck_id
    WHERE  ebr.id = p_booking_id
      AND  (ebr.requester_id = auth.uid() OR ft.owner_id = auth.uid())
  )
$$;


ALTER FUNCTION "public"."auth_user_in_booking"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auth_user_is_employee"("p_truck_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM truck_employees
    WHERE truck_id = p_truck_id AND user_id = auth.uid() AND status = 'active'
  );
$$;


ALTER FUNCTION "public"."auth_user_is_employee"("p_truck_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auth_user_owns_truck"("p_truck_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM food_trucks
    WHERE id = p_truck_id AND owner_id = auth.uid()
  );
$$;


ALTER FUNCTION "public"."auth_user_owns_truck"("p_truck_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auth_user_works_for_truck"("p_truck_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM truck_employees
    WHERE truck_id = p_truck_id
      AND user_id = auth.uid()
      AND status = 'active'
  );
$$;


ALTER FUNCTION "public"."auth_user_works_for_truck"("p_truck_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_owner_review_response"("p_review_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE reviews
  SET
    owner_response     = null,
    owner_responded_at = null
  WHERE id = p_review_id
    AND truck_id IN (
      SELECT id FROM food_trucks WHERE owner_id = auth.uid()
    );
END;
$$;


ALTER FUNCTION "public"."delete_owner_review_response"("p_review_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_profile_by_email"("p_email" "text") RETURNS TABLE("id" "uuid", "display_name" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT p.id, p.display_name FROM profiles p WHERE lower(p.email) = lower(p_email) LIMIT 1;
$$;


ALTER FUNCTION "public"."find_profile_by_email"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transfer_counterparty"("p_transfer_id" "uuid") RETURNS TABLE("display_name" "text", "email" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_from uuid;
  v_to uuid;
BEGIN
  SELECT from_owner_id, to_user_id INTO v_from, v_to
  FROM truck_transfers WHERE id = p_transfer_id;

  IF v_from IS NULL THEN
    RETURN;
  END IF;

  IF auth.uid() = v_from THEN
    RETURN QUERY SELECT p.display_name, p.email FROM profiles p WHERE p.id = v_to;
  ELSIF auth.uid() = v_to THEN
    RETURN QUERY SELECT p.display_name, p.email FROM profiles p WHERE p.id = v_from;
  END IF;
END;
$$;


ALTER FUNCTION "public"."get_transfer_counterparty"("p_transfer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_truck_follower_count"("p_truck_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COUNT(*)::integer FROM favorites WHERE truck_id = p_truck_id;
$$;


ALTER FUNCTION "public"."get_truck_follower_count"("p_truck_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."invite_employee_by_email"("p_truck_id" "uuid", "p_email" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_profile_id uuid;
  v_display_name text;
BEGIN
  -- Ownership check: only the truck's own owner may invite employees to it.
  -- Previously missing entirely, allowing any authenticated caller to add
  -- themselves (or anyone) as an active employee of any truck.
  IF NOT auth_user_owns_truck(p_truck_id) THEN
    RAISE EXCEPTION 'Not authorized: you do not own this truck' USING ERRCODE = '42501';
  END IF;

  -- Look up existing account by email
  SELECT id, display_name
  INTO v_profile_id, v_display_name
  FROM profiles
  WHERE lower(email) = lower(p_email)
  LIMIT 1;

  IF v_profile_id IS NOT NULL THEN
    -- Account exists — add immediately as active
    INSERT INTO truck_employees (truck_id, invited_email, user_id, status, linked_at)
    VALUES (p_truck_id, lower(p_email), v_profile_id, 'active', now());
    RETURN jsonb_build_object('already_user', true, 'display_name', v_display_name);
  ELSE
    -- No account yet — pending until they sign up
    INSERT INTO truck_employees (truck_id, invited_email, status)
    VALUES (p_truck_id, lower(p_email), 'pending');
    RETURN jsonb_build_object('already_user', false, 'display_name', null);
  END IF;
END;
$$;


ALTER FUNCTION "public"."invite_employee_by_email"("p_truck_id" "uuid", "p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_reviewer_on_response"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_truck_name text;
BEGIN
  IF NEW.owner_response IS NOT NULL AND NEW.owner_response != ''
     AND (OLD.owner_response IS NULL OR OLD.owner_response = '') THEN
    SELECT name INTO v_truck_name FROM food_trucks WHERE id = NEW.truck_id;

    INSERT INTO notifications (user_id, type, title, body, related_id)
    VALUES (
      NEW.user_id,
      'review_response',
      v_truck_name,
      'The owner responded to your review',
      NEW.truck_id
    );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_reviewer_on_response"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_truck_owner_on_review"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_owner_id uuid;
BEGIN
  SELECT owner_id INTO v_owner_id FROM food_trucks WHERE id = NEW.truck_id;

  IF v_owner_id IS NOT NULL AND v_owner_id != NEW.user_id THEN
    INSERT INTO notifications (user_id, type, title, body, related_id)
    VALUES (
      v_owner_id,
      'new_review',
      'New review',
      NEW.user_display_name || ' left you a ' || NEW.rating || E'★' || ' review',
      NEW.truck_id
    );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_truck_owner_on_review"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."owner_has_active_subscription"("p_owner_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE owner_id = p_owner_id
    AND status IN ('active', 'trialing')
  );
$$;


ALTER FUNCTION "public"."owner_has_active_subscription"("p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profile_display_name"("p_user_id" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT display_name FROM profiles WHERE id = p_user_id;
$$;


ALTER FUNCTION "public"."profile_display_name"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profile_stripe_connected"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT (stripe_account_id IS NOT NULL) FROM profiles WHERE id = p_user_id;
$$;


ALTER FUNCTION "public"."profile_stripe_connected"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."restrict_employee_scheduled_shift_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF auth_user_owns_truck(OLD.truck_id) THEN
    RETURN NEW;
  END IF;

  IF auth.uid() = OLD.employee_id THEN
    IF NEW.truck_id IS DISTINCT FROM OLD.truck_id
      OR NEW.employee_id IS DISTINCT FROM OLD.employee_id
      OR NEW.scheduled_start IS DISTINCT FROM OLD.scheduled_start
      OR NEW.scheduled_end IS DISTINCT FROM OLD.scheduled_end
      OR NEW.notes IS DISTINCT FROM OLD.notes
      OR NEW.created_by IS DISTINCT FROM OLD.created_by
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
      RAISE EXCEPTION 'Employees may only update the status of their own scheduled shift' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."restrict_employee_scheduled_shift_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_owner_review_response"("p_review_id" "uuid", "p_response" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE reviews
  SET
    owner_response     = p_response,
    owner_responded_at = now()
  WHERE id = p_review_id
    AND truck_id IN (
      SELECT id FROM food_trucks WHERE owner_id = auth.uid()
    );
END;
$$;


ALTER FUNCTION "public"."set_owner_review_response"("p_review_id" "uuid", "p_response" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_send_consumer_welcome_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  PERFORM extensions.http_post(
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


ALTER FUNCTION "public"."trigger_send_consumer_welcome_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_send_owner_onboarding_emails"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Mark sent first to block any recursive UPDATE from re-triggering
  UPDATE public.subscriptions
    SET onboarding_emails_sent_at = NOW()
    WHERE id = NEW.id;

  PERFORM extensions.http_post(
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


ALTER FUNCTION "public"."trigger_send_owner_onboarding_emails"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_truck_rating"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  _truck_id uuid;
BEGIN
  _truck_id := COALESCE(NEW.truck_id, OLD.truck_id);
  UPDATE food_trucks
  SET
    average_rating = (SELECT COALESCE(AVG(rating::float4), 0) FROM reviews WHERE truck_id = _truck_id),
    review_count   = (SELECT COUNT(*) FROM reviews WHERE truck_id = _truck_id)
  WHERE id = _truck_id;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."update_truck_rating"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."agent_directives" (
    "directive_key" "text" NOT NULL,
    "content" "text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text" DEFAULT 'aiden'::"text" NOT NULL,
    "locked" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."agent_directives" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_inbox_replies" (
    "thread_id" "text" NOT NULL,
    "replied_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."agent_inbox_replies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_run_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "agent_name" "text" NOT NULL,
    "run_mode" "text",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "finished_at" timestamp with time zone,
    "status" "text" DEFAULT 'running'::"text" NOT NULL,
    "error_detail" "text",
    "summary" "text",
    "input_tokens" integer,
    "output_tokens" integer,
    "cache_creation_tokens" integer,
    "cache_read_tokens" integer,
    "web_search_requests" integer,
    "model" "text",
    CONSTRAINT "agent_run_log_status_check" CHECK (("status" = ANY (ARRAY['running'::"text", 'success'::"text", 'partial'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."agent_run_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_deposits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "notes" "text",
    "due_date" "date",
    "status" "text" DEFAULT 'requested'::"text" NOT NULL,
    "stripe_payment_intent_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "booking_deposits_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "booking_deposits_status_check" CHECK (("status" = ANY (ARRAY['requested'::"text", 'paid'::"text", 'refunded'::"text"])))
);


ALTER TABLE "public"."booking_deposits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."booking_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_quotes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "amount" numeric(10,2) NOT NULL,
    "notes" "text",
    "status" "text" DEFAULT 'sent'::"text" NOT NULL,
    "stripe_payment_intent_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "booking_quotes_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "booking_quotes_status_check" CHECK (("status" = ANY (ARRAY['sent'::"text", 'accepted'::"text", 'declined'::"text", 'paid'::"text"]))),
    CONSTRAINT "booking_quotes_type_check" CHECK (("type" = ANY (ARRAY['estimate'::"text", 'invoice'::"text"])))
);


ALTER TABLE "public"."booking_quotes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "platform" "text" NOT NULL,
    "caption" "text" NOT NULL,
    "hashtags" "text",
    "visual_description" "text",
    "canva_link" "text",
    "needs_asset" boolean DEFAULT false NOT NULL,
    "status" "text" DEFAULT 'queued'::"text" NOT NULL,
    "posted_at" timestamp with time zone,
    "notes" "text",
    CONSTRAINT "content_queue_platform_check" CHECK (("platform" = ANY (ARRAY['tiktok'::"text", 'instagram'::"text", 'facebook'::"text", 'x'::"text", 'email'::"text"]))),
    CONSTRAINT "content_queue_status_check" CHECK (("status" = ANY (ARRAY['queued'::"text", 'posted'::"text", 'skipped'::"text"])))
);


ALTER TABLE "public"."content_queue" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employee_shifts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "clocked_in_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "clocked_out_at" timestamp with time zone,
    "location_address" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."employee_shifts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."event_booking_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "requester_id" "uuid",
    "contact_name" "text" NOT NULL,
    "contact_email" "text" NOT NULL,
    "contact_phone" "text",
    "event_date" "date" NOT NULL,
    "event_time" "text" NOT NULL,
    "guest_count" integer,
    "event_location" "text" NOT NULL,
    "event_type" "text" DEFAULT 'other'::"text" NOT NULL,
    "notes" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "duration" "text",
    "cancellation_reason" "text",
    "cancelled_by" "text",
    "other_trucks_present" boolean,
    "other_trucks_count" integer,
    CONSTRAINT "event_booking_requests_cancelled_by_check" CHECK (("cancelled_by" = ANY (ARRAY['owner'::"text", 'consumer'::"text"]))),
    CONSTRAINT "event_booking_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."event_booking_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."favorites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."favorites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."follower_notification_preferences" (
    "follower_id" "uuid" NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "announcements_enabled" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."follower_notification_preferences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."food_trucks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "cuisine_type" "text" DEFAULT 'Other'::"text" NOT NULL,
    "description" "text",
    "logo_url" "text",
    "photo_urls" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "menu_pdf_url" "text",
    "menu_image_url" "text",
    "latitude" double precision,
    "longitude" double precision,
    "location_updated_at" timestamp with time zone,
    "average_rating" real DEFAULT 0 NOT NULL,
    "review_count" integer DEFAULT 0 NOT NULL,
    "is_open" boolean DEFAULT false NOT NULL,
    "is_active" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "address" "text",
    "social_instagram" "text",
    "social_tiktok" "text",
    "social_facebook" "text",
    "social_twitter" "text",
    "social_youtube" "text",
    "website_url" "text",
    "session_started_at" timestamp with time zone,
    "cancellation_policy_hours" integer,
    "orders_enabled" boolean DEFAULT false NOT NULL,
    "opened_by_user_id" "uuid",
    "orders_accepting" boolean DEFAULT true NOT NULL,
    "business_type" "text" DEFAULT 'mobile'::"text" NOT NULL,
    "has_ever_opened" boolean DEFAULT false NOT NULL,
    "last_open_check_notified_at" timestamp with time zone
);


ALTER TABLE "public"."food_trucks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."menu_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "price" numeric(8,2) DEFAULT 0 NOT NULL,
    "image_url" "text",
    "category" "text" DEFAULT 'Mains'::"text" NOT NULL,
    "is_available" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."menu_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_preferences" (
    "user_id" "uuid" NOT NULL,
    "push_enabled" boolean DEFAULT true NOT NULL,
    "open_alert" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "announcement_alert" boolean DEFAULT true NOT NULL,
    "booking_alert" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."notification_preferences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "read" boolean DEFAULT false NOT NULL,
    "related_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."operating_hours" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "day_of_week" integer NOT NULL,
    "open_time" time without time zone,
    "close_time" time without time zone,
    "is_closed" boolean DEFAULT false NOT NULL,
    CONSTRAINT "operating_hours_day_of_week_check" CHECK ((("day_of_week" >= 0) AND ("day_of_week" <= 6)))
);


ALTER TABLE "public"."operating_hours" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "menu_item_id" "uuid",
    "menu_item_name" "text" NOT NULL,
    "menu_item_price" numeric(10,2) NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL,
    "special_request" "text"
);


ALTER TABLE "public"."order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "consumer_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "pickup_note" "text",
    "total_price" numeric(10,2) NOT NULL,
    "stripe_payment_intent_id" "text",
    "payment_status" "text" DEFAULT 'unpaid'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "orders_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['unpaid'::"text", 'paid'::"text", 'refunded'::"text"]))),
    CONSTRAINT "orders_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'ready'::"text", 'completed'::"text", 'declined'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."planned_locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "event_date" "date" NOT NULL,
    "title" "text" NOT NULL,
    "address" "text",
    "latitude" double precision,
    "longitude" double precision,
    "notes" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."planned_locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "avatar_url" "text",
    "role" "text" DEFAULT 'consumer'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stripe_account_id" "text",
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['consumer'::"text", 'owner'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_tokens" (
    "user_id" "uuid" NOT NULL,
    "platform" "text" NOT NULL,
    "token" "text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "push_tokens_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text"])))
);


ALTER TABLE "public"."push_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "user_display_name" "text" NOT NULL,
    "rating" integer NOT NULL,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_avatar_url" "text",
    "owner_response" "text",
    "owner_responded_at" timestamp with time zone,
    CONSTRAINT "reviews_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."reviews" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales_prospects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "business_name" "text" NOT NULL,
    "business_type" "text",
    "address" "text",
    "city" "text",
    "state" "text",
    "phone" "text",
    "website" "text",
    "google_place_id" "text",
    "status" "text" DEFAULT 'uncontacted'::"text" NOT NULL,
    "outreach_email" "text",
    "last_contacted_at" timestamp with time zone,
    "response_notes" "text",
    "converted_owner_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sales_prospects_status_check" CHECK (("status" = ANY (ARRAY['uncontacted'::"text", 'contacted'::"text", 'responded'::"text", 'converted'::"text", 'not_interested'::"text", 'bounced'::"text"])))
);


ALTER TABLE "public"."sales_prospects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."scheduled_shifts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "scheduled_start" timestamp with time zone NOT NULL,
    "scheduled_end" timestamp with time zone NOT NULL,
    "notes" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "scheduled_shifts_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text"])))
);


ALTER TABLE "public"."scheduled_shifts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'trialing'::"text" NOT NULL,
    "revenuecat_customer_id" "text",
    "product_identifier" "text",
    "current_period_end" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "onboarding_emails_sent_at" timestamp with time zone,
    "onboarding_email3_sent_at" timestamp with time zone
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."supervisor_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "week_of" "date" NOT NULL,
    "report_content" "text" NOT NULL,
    "critical_flags" "text"[],
    "top_actions" "text"[]
);


ALTER TABLE "public"."supervisor_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."support_tickets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "from_email" "text" NOT NULL,
    "from_name" "text",
    "subject" "text" NOT NULL,
    "body" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "priority" "text" DEFAULT 'normal'::"text" NOT NULL,
    "type" "text",
    "user_id" "uuid",
    "conversation" "jsonb" DEFAULT '[]'::"jsonb",
    "gmail_thread_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "urgent_alert_sent_at" timestamp with time zone,
    "escalation_reason" "text",
    "ticket_number" integer NOT NULL,
    CONSTRAINT "support_tickets_priority_check" CHECK (("priority" = ANY (ARRAY['low'::"text", 'normal'::"text", 'high'::"text", 'urgent'::"text"]))),
    CONSTRAINT "support_tickets_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'resolved'::"text", 'closed'::"text"]))),
    CONSTRAINT "support_tickets_type_check" CHECK (("type" = ANY (ARRAY['technical'::"text", 'billing'::"text", 'account'::"text", 'feature_request'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."support_tickets" OWNER TO "postgres";


ALTER TABLE "public"."support_tickets" ALTER COLUMN "ticket_number" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."support_tickets_ticket_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."truck_employees" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "invited_email" "text" NOT NULL,
    "user_id" "uuid",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "invited_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "linked_at" timestamp with time zone,
    CONSTRAINT "truck_employees_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'removed'::"text"])))
);


ALTER TABLE "public"."truck_employees" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."truck_transfers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "truck_id" "uuid" NOT NULL,
    "from_owner_id" "uuid" NOT NULL,
    "to_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval) NOT NULL,
    CONSTRAINT "truck_transfers_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."truck_transfers" OWNER TO "postgres";


ALTER TABLE ONLY "public"."agent_directives"
    ADD CONSTRAINT "agent_directives_pkey" PRIMARY KEY ("directive_key");



ALTER TABLE ONLY "public"."agent_inbox_replies"
    ADD CONSTRAINT "agent_inbox_replies_pkey" PRIMARY KEY ("thread_id");



ALTER TABLE ONLY "public"."agent_run_log"
    ADD CONSTRAINT "agent_run_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_deposits"
    ADD CONSTRAINT "booking_deposits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_messages"
    ADD CONSTRAINT "booking_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_quotes"
    ADD CONSTRAINT "booking_quotes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_queue"
    ADD CONSTRAINT "content_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."employee_shifts"
    ADD CONSTRAINT "employee_shifts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."event_booking_requests"
    ADD CONSTRAINT "event_booking_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_user_id_truck_id_key" UNIQUE ("user_id", "truck_id");



ALTER TABLE ONLY "public"."follower_notification_preferences"
    ADD CONSTRAINT "follower_notification_preferences_pkey" PRIMARY KEY ("follower_id", "truck_id");



ALTER TABLE ONLY "public"."food_trucks"
    ADD CONSTRAINT "food_trucks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."menu_items"
    ADD CONSTRAINT "menu_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."operating_hours"
    ADD CONSTRAINT "operating_hours_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."operating_hours"
    ADD CONSTRAINT "operating_hours_truck_id_day_of_week_key" UNIQUE ("truck_id", "day_of_week");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."planned_locations"
    ADD CONSTRAINT "planned_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("user_id", "platform");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_truck_id_user_id_key" UNIQUE ("truck_id", "user_id");



ALTER TABLE ONLY "public"."sales_prospects"
    ADD CONSTRAINT "sales_prospects_google_place_id_key" UNIQUE ("google_place_id");



ALTER TABLE ONLY "public"."sales_prospects"
    ADD CONSTRAINT "sales_prospects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."scheduled_shifts"
    ADD CONSTRAINT "scheduled_shifts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_owner_id_key" UNIQUE ("owner_id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supervisor_reports"
    ADD CONSTRAINT "supervisor_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."truck_employees"
    ADD CONSTRAINT "truck_employees_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."truck_transfers"
    ADD CONSTRAINT "truck_transfers_pkey" PRIMARY KEY ("id");



CREATE INDEX "agent_run_log_agent_name_started_at_idx" ON "public"."agent_run_log" USING "btree" ("agent_name", "started_at" DESC);



CREATE INDEX "idx_favorites_user" ON "public"."favorites" USING "btree" ("user_id");



CREATE INDEX "idx_menu_items_truck" ON "public"."menu_items" USING "btree" ("truck_id", "sort_order");



CREATE INDEX "idx_operating_hours_truck" ON "public"."operating_hours" USING "btree" ("truck_id", "day_of_week");



CREATE INDEX "idx_reviews_truck" ON "public"."reviews" USING "btree" ("truck_id", "created_at" DESC);



CREATE INDEX "notifications_user_id_created_at_idx" ON "public"."notifications" USING "btree" ("user_id", "created_at" DESC);



CREATE UNIQUE INDEX "one_pending_transfer_per_truck" ON "public"."truck_transfers" USING "btree" ("truck_id") WHERE ("status" = 'pending'::"text");



CREATE UNIQUE INDEX "support_tickets_ticket_number_idx" ON "public"."support_tickets" USING "btree" ("ticket_number");



CREATE UNIQUE INDEX "truck_employees_unique_active" ON "public"."truck_employees" USING "btree" ("truck_id", "lower"("invited_email")) WHERE ("status" <> 'removed'::"text");



CREATE OR REPLACE TRIGGER "food_trucks_set_updated_at" BEFORE UPDATE ON "public"."food_trucks" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "on_consumer_profile_created" AFTER INSERT ON "public"."profiles" FOR EACH ROW WHEN (("new"."role" = 'consumer'::"text")) EXECUTE FUNCTION "public"."trigger_send_consumer_welcome_email"();



CREATE OR REPLACE TRIGGER "on_review_inserted" AFTER INSERT ON "public"."reviews" FOR EACH ROW EXECUTE FUNCTION "public"."notify_truck_owner_on_review"();



CREATE OR REPLACE TRIGGER "on_review_response_added" AFTER UPDATE ON "public"."reviews" FOR EACH ROW EXECUTE FUNCTION "public"."notify_reviewer_on_response"();



CREATE OR REPLACE TRIGGER "on_subscription_onboarding_eligible" AFTER INSERT OR UPDATE ON "public"."subscriptions" FOR EACH ROW WHEN ((("new"."status" = ANY (ARRAY['trialing'::"text", 'active'::"text"])) AND ("new"."onboarding_emails_sent_at" IS NULL))) EXECUTE FUNCTION "public"."trigger_send_owner_onboarding_emails"();



CREATE OR REPLACE TRIGGER "restrict_employee_scheduled_shift_update_trigger" BEFORE UPDATE ON "public"."scheduled_shifts" FOR EACH ROW EXECUTE FUNCTION "public"."restrict_employee_scheduled_shift_update"();



CREATE OR REPLACE TRIGGER "trg_update_truck_rating" AFTER INSERT OR DELETE OR UPDATE ON "public"."reviews" FOR EACH ROW EXECUTE FUNCTION "public"."update_truck_rating"();



ALTER TABLE ONLY "public"."booking_deposits"
    ADD CONSTRAINT "booking_deposits_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."event_booking_requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_messages"
    ADD CONSTRAINT "booking_messages_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."event_booking_requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_messages"
    ADD CONSTRAINT "booking_messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."booking_quotes"
    ADD CONSTRAINT "booking_quotes_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."event_booking_requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_shifts"
    ADD CONSTRAINT "employee_shifts_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."employee_shifts"
    ADD CONSTRAINT "employee_shifts_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."event_booking_requests"
    ADD CONSTRAINT "event_booking_requests_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."event_booking_requests"
    ADD CONSTRAINT "event_booking_requests_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follower_notification_preferences"
    ADD CONSTRAINT "follower_notification_preferences_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follower_notification_preferences"
    ADD CONSTRAINT "follower_notification_preferences_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."food_trucks"
    ADD CONSTRAINT "food_trucks_opened_by_user_id_fkey" FOREIGN KEY ("opened_by_user_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."food_trucks"
    ADD CONSTRAINT "food_trucks_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."menu_items"
    ADD CONSTRAINT "menu_items_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."operating_hours"
    ADD CONSTRAINT "operating_hours_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_menu_item_id_fkey" FOREIGN KEY ("menu_item_id") REFERENCES "public"."menu_items"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_consumer_id_fkey" FOREIGN KEY ("consumer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."planned_locations"
    ADD CONSTRAINT "planned_locations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."planned_locations"
    ADD CONSTRAINT "planned_locations_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_prospects"
    ADD CONSTRAINT "sales_prospects_converted_owner_id_fkey" FOREIGN KEY ("converted_owner_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."scheduled_shifts"
    ADD CONSTRAINT "scheduled_shifts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."scheduled_shifts"
    ADD CONSTRAINT "scheduled_shifts_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."scheduled_shifts"
    ADD CONSTRAINT "scheduled_shifts_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."truck_employees"
    ADD CONSTRAINT "truck_employees_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."truck_employees"
    ADD CONSTRAINT "truck_employees_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."truck_transfers"
    ADD CONSTRAINT "truck_transfers_from_owner_id_fkey" FOREIGN KEY ("from_owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."truck_transfers"
    ADD CONSTRAINT "truck_transfers_to_user_id_fkey" FOREIGN KEY ("to_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."truck_transfers"
    ADD CONSTRAINT "truck_transfers_truck_id_fkey" FOREIGN KEY ("truck_id") REFERENCES "public"."food_trucks"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can read active trucks" ON "public"."food_trucks" FOR SELECT USING (("is_active" = true));



CREATE POLICY "Consumer can read and pay deposits" ON "public"."booking_deposits" USING ((EXISTS ( SELECT 1
   FROM "public"."event_booking_requests" "ebr"
  WHERE (("ebr"."id" = "booking_deposits"."booking_id") AND ("ebr"."requester_id" = "auth"."uid"())))));



CREATE POLICY "Consumer can read and respond to quotes" ON "public"."booking_quotes" USING ((EXISTS ( SELECT 1
   FROM "public"."event_booking_requests" "ebr"
  WHERE (("ebr"."id" = "booking_quotes"."booking_id") AND ("ebr"."requester_id" = "auth"."uid"())))));



CREATE POLICY "Owner can manage deposits" ON "public"."booking_deposits" USING ((EXISTS ( SELECT 1
   FROM ("public"."event_booking_requests" "ebr"
     JOIN "public"."food_trucks" "ft" ON (("ft"."id" = "ebr"."truck_id")))
  WHERE (("ebr"."id" = "booking_deposits"."booking_id") AND ("ft"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owner can manage quotes" ON "public"."booking_quotes" USING ((EXISTS ( SELECT 1
   FROM ("public"."event_booking_requests" "ebr"
     JOIN "public"."food_trucks" "ft" ON (("ft"."id" = "ebr"."truck_id")))
  WHERE (("ebr"."id" = "booking_quotes"."booking_id") AND ("ft"."owner_id" = "auth"."uid"())))));



CREATE POLICY "Owners manage their own truck" ON "public"."food_trucks" USING (("auth"."uid"() = "owner_id")) WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "Owners read their own subscription" ON "public"."subscriptions" FOR SELECT USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "Service role manages subscriptions" ON "public"."subscriptions" USING (("auth"."role"() = 'service_role'::"text"));



CREATE POLICY "Users manage own notification prefs" ON "public"."notification_preferences" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."agent_directives" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_inbox_replies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_run_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_deposits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_quotes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "consumers can cancel own requests" ON "public"."event_booking_requests" FOR UPDATE USING ((("requester_id" = "auth"."uid"()) AND ("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text"])))) WITH CHECK ((("requester_id" = "auth"."uid"()) AND ("status" = 'cancelled'::"text") AND ("cancelled_by" = 'consumer'::"text")));



CREATE POLICY "consumers can insert booking requests" ON "public"."event_booking_requests" FOR INSERT TO "authenticated" WITH CHECK (("requester_id" = "auth"."uid"()));



CREATE POLICY "consumers_read_planned_locations" ON "public"."planned_locations" FOR SELECT USING (true);



ALTER TABLE "public"."content_queue" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "employee_claim_invite" ON "public"."truck_employees" FOR UPDATE USING ((("lower"("invited_email") = "lower"(("auth"."jwt"() ->> 'email'::"text"))) AND ("status" = 'pending'::"text"))) WITH CHECK ((("user_id" = "auth"."uid"()) AND ("status" = 'active'::"text")));



CREATE POLICY "employee_select_assigned_truck" ON "public"."food_trucks" FOR SELECT USING ("public"."auth_user_is_employee"("id"));



CREATE POLICY "employee_select_scheduled_shifts" ON "public"."scheduled_shifts" FOR SELECT USING (("auth"."uid"() = "employee_id"));



ALTER TABLE "public"."employee_shifts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "employee_shifts_insert_own" ON "public"."employee_shifts" FOR INSERT WITH CHECK ((("auth"."uid"() = "employee_id") AND (("clocked_in_at" >= ("now"() - '00:10:00'::interval)) AND ("clocked_in_at" <= ("now"() + '00:10:00'::interval)))));



CREATE POLICY "employee_shifts_select_own" ON "public"."employee_shifts" FOR SELECT USING (("auth"."uid"() = "employee_id"));



CREATE POLICY "employee_shifts_select_owner" ON "public"."employee_shifts" FOR SELECT USING ("public"."auth_user_owns_truck"("truck_id"));



CREATE POLICY "employee_shifts_update_own" ON "public"."employee_shifts" FOR UPDATE USING ((("auth"."uid"() = "employee_id") AND ("clocked_out_at" IS NULL))) WITH CHECK ((("auth"."uid"() = "employee_id") AND (("clocked_out_at" >= ("now"() - '00:10:00'::interval)) AND ("clocked_out_at" <= ("now"() + '00:10:00'::interval)))));



CREATE POLICY "employee_update_status_scheduled_shifts" ON "public"."scheduled_shifts" FOR UPDATE USING (("auth"."uid"() = "employee_id")) WITH CHECK (("auth"."uid"() = "employee_id"));



CREATE POLICY "employee_update_truck_live" ON "public"."food_trucks" FOR UPDATE USING ("public"."auth_user_is_employee"("id")) WITH CHECK ("public"."auth_user_is_employee"("id"));



CREATE POLICY "employee_view_own" ON "public"."truck_employees" FOR SELECT USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."event_booking_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."favorites" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "favorites_delete_own" ON "public"."favorites" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "favorites_insert_own" ON "public"."favorites" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "favorites_select_own" ON "public"."favorites" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."follower_notification_preferences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."food_trucks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "food_trucks: anyone can read active trucks" ON "public"."food_trucks" FOR SELECT USING (("is_active" = true));



CREATE POLICY "food_trucks: owner can insert" ON "public"."food_trucks" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "food_trucks: owner can read own truck" ON "public"."food_trucks" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "food_trucks: owner can update" ON "public"."food_trucks" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "food_trucks_owner_update" ON "public"."food_trucks" FOR UPDATE TO "authenticated" USING (("owner_id" = "auth"."uid"())) WITH CHECK (("owner_id" = "auth"."uid"()));



ALTER TABLE "public"."menu_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "menu_items_delete" ON "public"."menu_items" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_items"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));



CREATE POLICY "menu_items_insert" ON "public"."menu_items" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_items"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));



CREATE POLICY "menu_items_read" ON "public"."menu_items" FOR SELECT USING (true);



CREATE POLICY "menu_items_update" ON "public"."menu_items" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_items"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "menu_items"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));



ALTER TABLE "public"."notification_preferences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."operating_hours" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "operating_hours_delete" ON "public"."operating_hours" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "operating_hours"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));



CREATE POLICY "operating_hours_insert" ON "public"."operating_hours" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "operating_hours"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));



CREATE POLICY "operating_hours_read" ON "public"."operating_hours" FOR SELECT USING (true);



CREATE POLICY "operating_hours_update" ON "public"."operating_hours" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "operating_hours"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."food_trucks"
  WHERE (("food_trucks"."id" = "operating_hours"."truck_id") AND ("food_trucks"."owner_id" = "auth"."uid"())))));



ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "order_items_insert" ON "public"."order_items" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "order_items"."order_id") AND ("o"."consumer_id" = "auth"."uid"())))));



CREATE POLICY "order_items_select" ON "public"."order_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "order_items"."order_id") AND (("o"."consumer_id" = "auth"."uid"()) OR "public"."auth_user_owns_truck"("o"."truck_id") OR "public"."auth_user_works_for_truck"("o"."truck_id"))))));



ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orders_consumer_insert" ON "public"."orders" FOR INSERT WITH CHECK (("consumer_id" = "auth"."uid"()));



CREATE POLICY "orders_consumer_select" ON "public"."orders" FOR SELECT USING ((("consumer_id" = "auth"."uid"()) OR "public"."auth_user_owns_truck"("truck_id") OR "public"."auth_user_works_for_truck"("truck_id")));



CREATE POLICY "orders_consumer_update" ON "public"."orders" FOR UPDATE USING (("consumer_id" = "auth"."uid"())) WITH CHECK (("status" = 'cancelled'::"text"));



CREATE POLICY "orders_employee_update" ON "public"."orders" FOR UPDATE USING ("public"."auth_user_works_for_truck"("truck_id"));



CREATE POLICY "orders_owner_update" ON "public"."orders" FOR UPDATE USING ("public"."auth_user_owns_truck"("truck_id"));



CREATE POLICY "owner can cancel transfer" ON "public"."truck_transfers" FOR UPDATE USING ((("from_owner_id" = "auth"."uid"()) AND ("status" = 'pending'::"text"))) WITH CHECK (("status" = 'cancelled'::"text"));



CREATE POLICY "owner can initiate transfer" ON "public"."truck_transfers" FOR INSERT WITH CHECK ((("from_owner_id" = "auth"."uid"()) AND "public"."auth_user_owns_truck"("truck_id")));



CREATE POLICY "owner sees own outgoing transfers" ON "public"."truck_transfers" FOR SELECT USING (("from_owner_id" = "auth"."uid"()));



CREATE POLICY "owner_all_scheduled_shifts" ON "public"."scheduled_shifts" USING ("public"."auth_user_owns_truck"("truck_id")) WITH CHECK ("public"."auth_user_owns_truck"("truck_id"));



CREATE POLICY "owner_manage_employees" ON "public"."truck_employees" USING ("public"."auth_user_owns_truck"("truck_id"));



CREATE POLICY "owner_update_employee_shifts" ON "public"."employee_shifts" FOR UPDATE USING ("public"."auth_user_owns_truck"("truck_id"));



CREATE POLICY "owners can insert manual bookings" ON "public"."event_booking_requests" FOR INSERT TO "authenticated" WITH CHECK (("public"."auth_user_owns_truck"("truck_id") AND ("requester_id" IS NULL)));



CREATE POLICY "owners can update request status" ON "public"."event_booking_requests" FOR UPDATE TO "authenticated" USING ("public"."auth_user_owns_truck"("truck_id")) WITH CHECK ("public"."auth_user_owns_truck"("truck_id"));



CREATE POLICY "owners can view requests for their truck" ON "public"."event_booking_requests" FOR SELECT TO "authenticated" USING ("public"."auth_user_owns_truck"("truck_id"));



CREATE POLICY "participants_insert" ON "public"."booking_messages" FOR INSERT WITH CHECK ((("sender_id" = "auth"."uid"()) AND "public"."auth_user_in_booking"("booking_id")));



CREATE POLICY "participants_select" ON "public"."booking_messages" FOR SELECT USING ("public"."auth_user_in_booking"("booking_id"));



ALTER TABLE "public"."planned_locations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles: owner can insert" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "profiles: owner can read own employees" ON "public"."profiles" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."truck_employees" "te"
  WHERE (("te"."user_id" = "profiles"."id") AND "public"."auth_user_owns_truck"("te"."truck_id")))));



CREATE POLICY "profiles: owner can update" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "profiles: self can read" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "profiles: truck can read consumer on orders" ON "public"."profiles" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."consumer_id" = "profiles"."id") AND ("public"."auth_user_owns_truck"("o"."truck_id") OR "public"."auth_user_works_for_truck"("o"."truck_id"))))));



ALTER TABLE "public"."push_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "recipient can decline transfer" ON "public"."truck_transfers" FOR UPDATE USING ((("to_user_id" = "auth"."uid"()) AND ("status" = 'pending'::"text"))) WITH CHECK (("status" = 'cancelled'::"text"));



CREATE POLICY "recipient can view incoming transfers" ON "public"."truck_transfers" FOR SELECT USING (("to_user_id" = "auth"."uid"()));



CREATE POLICY "requesters can view own requests" ON "public"."event_booking_requests" FOR SELECT TO "authenticated" USING (("requester_id" = "auth"."uid"()));



ALTER TABLE "public"."reviews" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reviews_delete_own" ON "public"."reviews" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "reviews_insert_consumer" ON "public"."reviews" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "reviews_select_all" ON "public"."reviews" FOR SELECT USING (true);



CREATE POLICY "reviews_update_own" ON "public"."reviews" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."sales_prospects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."scheduled_shifts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service role only" ON "public"."agent_directives" USING (false);



CREATE POLICY "service role only" ON "public"."agent_inbox_replies" USING (false);



CREATE POLICY "service role only" ON "public"."agent_run_log" USING (false);



CREATE POLICY "service role only" ON "public"."content_queue" USING (false);



CREATE POLICY "service role only" ON "public"."sales_prospects" USING (false);



CREATE POLICY "service role only" ON "public"."supervisor_reports" USING (false);



CREATE POLICY "service role only" ON "public"."support_tickets" USING (false);



CREATE POLICY "service_role_read_notification_prefs" ON "public"."follower_notification_preferences" FOR SELECT USING (("auth"."role"() = 'service_role'::"text"));



ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscriptions: owner can insert own" ON "public"."subscriptions" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "subscriptions: owner can read own" ON "public"."subscriptions" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "owner_id"));



ALTER TABLE "public"."supervisor_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."support_tickets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."truck_employees" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "truck_members_manage_planned_locations" ON "public"."planned_locations" USING (("truck_id" IN ( SELECT "food_trucks"."id"
   FROM "public"."food_trucks"
  WHERE ("food_trucks"."owner_id" = "auth"."uid"())
UNION
 SELECT "truck_employees"."truck_id"
   FROM "public"."truck_employees"
  WHERE (("truck_employees"."user_id" = "auth"."uid"()) AND ("truck_employees"."status" = 'active'::"text")))));



ALTER TABLE "public"."truck_transfers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users manage own push token" ON "public"."push_tokens" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "users_delete_own_notifications" ON "public"."notifications" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "users_manage_own_notification_prefs" ON "public"."follower_notification_preferences" USING (("follower_id" = "auth"."uid"()));



CREATE POLICY "users_select_own_notifications" ON "public"."notifications" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "users_update_own_notifications" ON "public"."notifications" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."booking_messages";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."event_booking_requests";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."food_trucks";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."menu_items";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."orders";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."scheduled_shifts";












GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";











































































































































































GRANT ALL ON FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_user_in_booking"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."auth_user_in_booking"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_user_in_booking"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_user_is_employee"("p_truck_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."auth_user_is_employee"("p_truck_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_user_is_employee"("p_truck_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_user_owns_truck"("p_truck_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."auth_user_owns_truck"("p_truck_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_user_owns_truck"("p_truck_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_user_works_for_truck"("p_truck_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."auth_user_works_for_truck"("p_truck_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_user_works_for_truck"("p_truck_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_owner_review_response"("p_review_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_owner_review_response"("p_review_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_owner_review_response"("p_review_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."find_profile_by_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."find_profile_by_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_profile_by_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transfer_counterparty"("p_transfer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transfer_counterparty"("p_transfer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transfer_counterparty"("p_transfer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_truck_follower_count"("p_truck_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_truck_follower_count"("p_truck_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_truck_follower_count"("p_truck_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."invite_employee_by_email"("p_truck_id" "uuid", "p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."invite_employee_by_email"("p_truck_id" "uuid", "p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."invite_employee_by_email"("p_truck_id" "uuid", "p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_reviewer_on_response"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_reviewer_on_response"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_reviewer_on_response"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_truck_owner_on_review"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_truck_owner_on_review"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_truck_owner_on_review"() TO "service_role";



GRANT ALL ON FUNCTION "public"."owner_has_active_subscription"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."owner_has_active_subscription"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."owner_has_active_subscription"("p_owner_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."profile_display_name"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."profile_display_name"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."profile_display_name"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."profile_stripe_connected"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."profile_stripe_connected"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."profile_stripe_connected"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."restrict_employee_scheduled_shift_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."restrict_employee_scheduled_shift_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."restrict_employee_scheduled_shift_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_owner_review_response"("p_review_id" "uuid", "p_response" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_owner_review_response"("p_review_id" "uuid", "p_response" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_owner_review_response"("p_review_id" "uuid", "p_response" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_send_consumer_welcome_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_send_consumer_welcome_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_send_consumer_welcome_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_send_owner_onboarding_emails"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_send_owner_onboarding_emails"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_send_owner_onboarding_emails"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_truck_rating"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_truck_rating"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_truck_rating"() TO "service_role";
























GRANT ALL ON TABLE "public"."agent_directives" TO "anon";
GRANT ALL ON TABLE "public"."agent_directives" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_directives" TO "service_role";



GRANT ALL ON TABLE "public"."agent_inbox_replies" TO "anon";
GRANT ALL ON TABLE "public"."agent_inbox_replies" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_inbox_replies" TO "service_role";



GRANT ALL ON TABLE "public"."agent_run_log" TO "anon";
GRANT ALL ON TABLE "public"."agent_run_log" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_run_log" TO "service_role";



GRANT ALL ON TABLE "public"."booking_deposits" TO "anon";
GRANT ALL ON TABLE "public"."booking_deposits" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_deposits" TO "service_role";



GRANT ALL ON TABLE "public"."booking_messages" TO "anon";
GRANT ALL ON TABLE "public"."booking_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_messages" TO "service_role";



GRANT ALL ON TABLE "public"."booking_quotes" TO "anon";
GRANT ALL ON TABLE "public"."booking_quotes" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_quotes" TO "service_role";



GRANT ALL ON TABLE "public"."content_queue" TO "anon";
GRANT ALL ON TABLE "public"."content_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."content_queue" TO "service_role";



GRANT ALL ON TABLE "public"."employee_shifts" TO "anon";
GRANT ALL ON TABLE "public"."employee_shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."employee_shifts" TO "service_role";



GRANT ALL ON TABLE "public"."event_booking_requests" TO "anon";
GRANT ALL ON TABLE "public"."event_booking_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."event_booking_requests" TO "service_role";



GRANT ALL ON TABLE "public"."favorites" TO "anon";
GRANT ALL ON TABLE "public"."favorites" TO "authenticated";
GRANT ALL ON TABLE "public"."favorites" TO "service_role";



GRANT ALL ON TABLE "public"."follower_notification_preferences" TO "anon";
GRANT ALL ON TABLE "public"."follower_notification_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."follower_notification_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."food_trucks" TO "anon";
GRANT ALL ON TABLE "public"."food_trucks" TO "authenticated";
GRANT ALL ON TABLE "public"."food_trucks" TO "service_role";



GRANT ALL ON TABLE "public"."menu_items" TO "anon";
GRANT ALL ON TABLE "public"."menu_items" TO "authenticated";
GRANT ALL ON TABLE "public"."menu_items" TO "service_role";



GRANT ALL ON TABLE "public"."notification_preferences" TO "anon";
GRANT ALL ON TABLE "public"."notification_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."operating_hours" TO "anon";
GRANT ALL ON TABLE "public"."operating_hours" TO "authenticated";
GRANT ALL ON TABLE "public"."operating_hours" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."planned_locations" TO "anon";
GRANT ALL ON TABLE "public"."planned_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."planned_locations" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."push_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."reviews" TO "anon";
GRANT ALL ON TABLE "public"."reviews" TO "authenticated";
GRANT ALL ON TABLE "public"."reviews" TO "service_role";



GRANT ALL ON TABLE "public"."sales_prospects" TO "anon";
GRANT ALL ON TABLE "public"."sales_prospects" TO "authenticated";
GRANT ALL ON TABLE "public"."sales_prospects" TO "service_role";



GRANT ALL ON TABLE "public"."scheduled_shifts" TO "anon";
GRANT ALL ON TABLE "public"."scheduled_shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."scheduled_shifts" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."supervisor_reports" TO "anon";
GRANT ALL ON TABLE "public"."supervisor_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."supervisor_reports" TO "service_role";



GRANT ALL ON TABLE "public"."support_tickets" TO "anon";
GRANT ALL ON TABLE "public"."support_tickets" TO "authenticated";
GRANT ALL ON TABLE "public"."support_tickets" TO "service_role";



GRANT ALL ON SEQUENCE "public"."support_tickets_ticket_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."support_tickets_ticket_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."support_tickets_ticket_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."truck_employees" TO "anon";
GRANT ALL ON TABLE "public"."truck_employees" TO "authenticated";
GRANT ALL ON TABLE "public"."truck_employees" TO "service_role";



GRANT ALL ON TABLE "public"."truck_transfers" TO "anon";
GRANT ALL ON TABLE "public"."truck_transfers" TO "authenticated";
GRANT ALL ON TABLE "public"."truck_transfers" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
































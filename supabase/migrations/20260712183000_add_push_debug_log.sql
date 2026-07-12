-- TEMPORARY diagnostic table for the push-notification registration
-- investigation (2026-07-12). Every prior Dart-level error signal came from
-- `flutter run --release`, which Phase 4 of the investigation proved is not
-- valid evidence for anything APNs-related (dev-signed, doesn't match the
-- app's hardcoded aps-environment: production entitlement). This table lets
-- the real TestFlight (distribution-signed) build write directly-queryable
-- evidence of what actually happens at each step of token registration,
-- without depending on Crashlytics dashboard propagation delay.
--
-- Drop this table once the root cause is confirmed and fixed -- it's not
-- meant to be permanent instrumentation.

CREATE TABLE IF NOT EXISTS "public"."debug_log" (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "user_id" uuid,
    "event" text NOT NULL,
    "detail" text
);

ALTER TABLE "public"."debug_log" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated users can insert their own debug logs"
    ON "public"."debug_log"
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

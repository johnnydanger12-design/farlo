-- Drops the temporary debug_log table added in
-- 20260712183000_add_push_debug_log.sql for the push-notification
-- registration investigation. Root cause found and fixed (see
-- ios/Runner/AppDelegate.swift) -- this table is no longer needed.

DROP TABLE IF EXISTS "public"."debug_log";

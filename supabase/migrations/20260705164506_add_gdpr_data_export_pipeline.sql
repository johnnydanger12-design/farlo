-- GDPR/CCPA right-to-portability: lets a user request a machine-readable
-- export of their own data. Built as an async request/fulfillment pipeline
-- (not a synchronous request-time compile) so it scales past this app's
-- current data volumes: a client-facing Edge Function only ever inserts a
-- request row and returns immediately; a cron-triggered worker
-- (process-data-exports) does the actual compilation, uploads to a private
-- Storage bucket, and hands back a short-lived signed URL, mirroring the
-- request/fulfillment shape already used for support-ticket-driven agent
-- work in this codebase (agent_cron_call + requireAgentSecret).

CREATE TABLE public.data_export_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'expired')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  expires_at timestamptz,
  storage_path text,
  download_url text,
  error_message text
);

-- At most one active (pending/processing) request per user — the client
-- checks this too for a friendlier error, but the constraint is the real
-- guarantee against a user (or a retried request) queuing unbounded work.
CREATE UNIQUE INDEX data_export_requests_one_active_per_user
  ON public.data_export_requests (user_id)
  WHERE status IN ('pending', 'processing');

CREATE INDEX data_export_requests_status_idx ON public.data_export_requests (status);

ALTER TABLE public.data_export_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own export requests"
  ON public.data_export_requests FOR SELECT
  USING (auth.uid() = user_id);

-- No client-facing INSERT/UPDATE policy: rows are only ever created by the
-- request-data-export Edge Function and only ever updated by the
-- process-data-exports cron worker, both using the service role key, which
-- bypasses RLS entirely — the same pattern already used for
-- agent_run_log/agent_tool_call_log.

-- Private bucket: every read goes through a short-lived signed URL minted
-- server-side by process-data-exports, never through a client-facing RLS
-- policy on storage.objects, so no policy is added here (the storage.objects
-- RLS default of "no policy = no access" is exactly what's wanted).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('data-exports', 'data-exports', false, 20971520, ARRAY['application/json']::text[]);

-- Compiles every row across the schema that belongs to p_user_id into one
-- JSON document. Mirrors delete_account_data()'s enumeration of "what
-- belongs to this user" (same migration family, same account) so the two
-- stay in sync by construction rather than by two independently-maintained
-- lists silently drifting apart. SECURITY DEFINER + a pinned search_path
-- (this session's established convention for SECURITY DEFINER functions)
-- since it's called via the service-role client from an Edge Function, not
-- directly by end users.
CREATE OR REPLACE FUNCTION public.compile_user_data_export(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_truck_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_truck_id FROM food_trucks WHERE owner_id = p_user_id;

  SELECT jsonb_build_object(
    'export_generated_at', now(),
    'user_id', p_user_id,
    'profile', (SELECT to_jsonb(p) FROM profiles p WHERE p.id = p_user_id),
    'favorites', (SELECT coalesce(jsonb_agg(f), '[]'::jsonb) FROM favorites f WHERE f.user_id = p_user_id),
    'reviews_written', (SELECT coalesce(jsonb_agg(r), '[]'::jsonb) FROM reviews r WHERE r.user_id = p_user_id),
    'notification_preferences', (SELECT to_jsonb(np) FROM notification_preferences np WHERE np.user_id = p_user_id),
    'follower_notification_preferences', (SELECT coalesce(jsonb_agg(fnp), '[]'::jsonb) FROM follower_notification_preferences fnp WHERE fnp.follower_id = p_user_id),
    'push_tokens', (SELECT coalesce(jsonb_agg(pt), '[]'::jsonb) FROM push_tokens pt WHERE pt.user_id = p_user_id),
    'orders_as_consumer', (
      SELECT coalesce(jsonb_agg(o_row), '[]'::jsonb)
      FROM (
        SELECT o.*, (SELECT coalesce(jsonb_agg(oi), '[]'::jsonb) FROM order_items oi WHERE oi.order_id = o.id) AS items
        FROM orders o WHERE o.consumer_id = p_user_id
      ) o_row
    ),
    'bookings_as_requester', (SELECT coalesce(jsonb_agg(ebr), '[]'::jsonb) FROM event_booking_requests ebr WHERE ebr.requester_id = p_user_id),
    'messages_sent', (SELECT coalesce(jsonb_agg(bm), '[]'::jsonb) FROM booking_messages bm WHERE bm.sender_id = p_user_id),
    'support_tickets', (SELECT coalesce(jsonb_agg(st), '[]'::jsonb) FROM support_tickets st WHERE st.user_id = p_user_id),
    'shifts_worked', (SELECT coalesce(jsonb_agg(es), '[]'::jsonb) FROM employee_shifts es WHERE es.employee_id = p_user_id),
    'shifts_scheduled', (SELECT coalesce(jsonb_agg(ss), '[]'::jsonb) FROM scheduled_shifts ss WHERE ss.employee_id = p_user_id),
    'truck_transfers', (SELECT coalesce(jsonb_agg(tt), '[]'::jsonb) FROM truck_transfers tt WHERE tt.from_owner_id = p_user_id OR tt.to_user_id = p_user_id),
    'owned_truck', CASE WHEN v_truck_id IS NULL THEN NULL ELSE (
      SELECT jsonb_build_object(
        'truck', (SELECT to_jsonb(ft) FROM food_trucks ft WHERE ft.id = v_truck_id),
        'menu_items', (SELECT coalesce(jsonb_agg(mi), '[]'::jsonb) FROM menu_items mi WHERE mi.truck_id = v_truck_id),
        'operating_hours', (SELECT coalesce(jsonb_agg(oh), '[]'::jsonb) FROM operating_hours oh WHERE oh.truck_id = v_truck_id),
        'bookings_received', (SELECT coalesce(jsonb_agg(ebr2), '[]'::jsonb) FROM event_booking_requests ebr2 WHERE ebr2.truck_id = v_truck_id),
        'booking_quotes', (SELECT coalesce(jsonb_agg(bq), '[]'::jsonb) FROM booking_quotes bq WHERE bq.booking_id IN (SELECT id FROM event_booking_requests WHERE truck_id = v_truck_id)),
        'booking_deposits', (SELECT coalesce(jsonb_agg(bd), '[]'::jsonb) FROM booking_deposits bd WHERE bd.booking_id IN (SELECT id FROM event_booking_requests WHERE truck_id = v_truck_id)),
        'employees', (SELECT coalesce(jsonb_agg(te), '[]'::jsonb) FROM truck_employees te WHERE te.truck_id = v_truck_id),
        'subscription', (SELECT to_jsonb(sub) FROM subscriptions sub WHERE sub.owner_id = p_user_id),
        'orders_received', (
          SELECT coalesce(jsonb_agg(o_row2), '[]'::jsonb)
          FROM (
            SELECT o2.*, (SELECT coalesce(jsonb_agg(oi2), '[]'::jsonb) FROM order_items oi2 WHERE oi2.order_id = o2.id) AS items
            FROM orders o2 WHERE o2.truck_id = v_truck_id
          ) o_row2
        )
      )
    ) END
  ) INTO v_result;

  RETURN v_result;
END;
$$;

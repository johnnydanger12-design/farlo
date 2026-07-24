-- New occasional consumer push nudge: "a business you follow is open right
-- now around lunchtime." lunch_nudge_alert is the opt-out toggle (mirrors
-- announcement_alert/booking_alert); last_lunch_nudge_sent_at is the per-user
-- cooldown stamp, kept here since this table is already the one-row-per-user
-- home for notification state (same reasoning as food_trucks.onboarding_nudge_sent_at
-- for the owner-side nudge).
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS lunch_nudge_alert boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS last_lunch_nudge_sent_at timestamp with time zone;

-- notification_preferences has zero rows for real consumers today (confirmed
-- live — it's only ever created lazily on first upsert from the Notifications
-- settings sheet), so candidate selection can't inner-join against it; this
-- function starts from profiles and treats a missing preferences row as the
-- same defaults the Flutter client itself falls back to (push_enabled=true,
-- lunch_nudge_alert=true). Only returns consumers with >=1 currently-open,
-- non-muted favorite — anyone with zero qualifies for nothing and is
-- deliberately absent from the result (no fallback message, no stamp).
CREATE OR REPLACE FUNCTION public.get_lunch_nudge_candidates(p_test_user_id uuid DEFAULT NULL)
RETURNS TABLE (
  user_id uuid,
  truck_ids uuid[],
  truck_names text[],
  push_enabled boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id AS user_id,
    array_agg(ft.id ORDER BY ft.name) AS truck_ids,
    array_agg(ft.name ORDER BY ft.name) AS truck_names,
    coalesce(np.push_enabled, true) AS push_enabled
  FROM profiles p
  JOIN favorites f ON f.user_id = p.id
  JOIN food_trucks ft ON ft.id = f.truck_id
    AND ft.is_active = true AND ft.is_open = true AND ft.orders_accepting = true
  LEFT JOIN follower_notification_preferences fnp
    ON fnp.follower_id = p.id AND fnp.truck_id = ft.id
  LEFT JOIN notification_preferences np ON np.user_id = p.id
  WHERE p.role = 'consumer'
    AND coalesce(np.lunch_nudge_alert, true) = true
    AND (np.last_lunch_nudge_sent_at IS NULL OR np.last_lunch_nudge_sent_at < now() - interval '10 days')
    AND coalesce(fnp.announcements_enabled, true) = true
    AND (p_test_user_id IS NULL OR p.id = p_test_user_id)
  GROUP BY p.id, np.push_enabled;
$$;

REVOKE ALL ON FUNCTION public.get_lunch_nudge_candidates(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_lunch_nudge_candidates(uuid) TO service_role;

-- profiles' SELECT policy was `USING (true)` for {authenticated} — every signed-in user
-- could read every other user's email + stripe_account_id, and profiles is realtime-
-- published so changes broadcast to the whole user base. Replace with self-only, and
-- add narrow SECURITY DEFINER functions (same least-privilege pattern already used by
-- auth_user_owns_truck/owner_has_active_subscription/get_truck_follower_count) for the
-- handful of legitimate cross-user lookups the app actually needs.

-- 1. Display name of an arbitrary user (e.g. "truck opened by <employee name>") — low
--    sensitivity, matches the existing get_truck_follower_count precedent.
CREATE OR REPLACE FUNCTION public.profile_display_name(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT display_name FROM profiles WHERE id = p_user_id;
$$;

-- 2. Whether a given user has Stripe Connect set up — needed by an employee's
--    dashboard to know if their owner can accept payments, without exposing the id.
CREATE OR REPLACE FUNCTION public.profile_stripe_connected(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT (stripe_account_id IS NOT NULL) FROM profiles WHERE id = p_user_id;
$$;

-- 3. Look up an account by email for the truck-transfer flow (an owner searching for
--    who they're transferring the business to). Returns only id + display_name — the
--    caller already knows the email they typed, no need to echo it back.
CREATE OR REPLACE FUNCTION public.find_profile_by_email(p_email text)
RETURNS TABLE(id uuid, display_name text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT p.id, p.display_name FROM profiles p WHERE lower(p.email) = lower(p_email) LIMIT 1;
$$;

-- 4. The other party's name/email on a specific truck transfer — scoped to callers who
--    are actually a party (from_owner or to_user) to that exact transfer row, not a
--    generic profile-by-id lookup.
CREATE OR REPLACE FUNCTION public.get_transfer_counterparty(p_transfer_id uuid)
RETURNS TABLE(display_name text, email text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
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

DROP POLICY IF EXISTS "profiles: authenticated can read" ON public.profiles;
DROP POLICY IF EXISTS "profiles: self can read" ON public.profiles;
CREATE POLICY "profiles: self can read" ON public.profiles
  FOR SELECT
  USING (auth.uid() = id);

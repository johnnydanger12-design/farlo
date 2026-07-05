CREATE OR REPLACE FUNCTION public.invite_employee_by_email(p_truck_id uuid, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

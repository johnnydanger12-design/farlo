-- delete-account previously never cleared 4 NO ACTION foreign keys
-- (booking_messages.sender_id, food_trucks.opened_by_user_id,
-- support_tickets.user_id, sales_prospects.converted_owner_id), so the final
-- auth.admin.deleteUser() call could throw partway through, leaving a
-- half-deleted "zombie" account (data gone, auth.users row still present,
-- login still works) — security.md N2 / FARLO_FINAL_AUDIT.md Top 20 #7.
-- This function does all app-data cleanup in one atomic transaction (a
-- Postgres function's effects roll back together on any failure), including
-- clearing the four blockers, so the Edge Function's subsequent
-- auth.admin.deleteUser() call has nothing left to violate.
CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_truck_id uuid;
BEGIN
  DELETE FROM booking_messages WHERE sender_id = p_user_id;
  UPDATE food_trucks SET opened_by_user_id = NULL WHERE opened_by_user_id = p_user_id;
  UPDATE support_tickets SET user_id = NULL WHERE user_id = p_user_id;
  UPDATE sales_prospects SET converted_owner_id = NULL WHERE converted_owner_id = p_user_id;

  DELETE FROM push_tokens WHERE user_id = p_user_id;
  DELETE FROM favorites WHERE user_id = p_user_id;
  DELETE FROM reviews WHERE user_id = p_user_id;
  DELETE FROM event_booking_requests WHERE requester_id = p_user_id;

  SELECT id INTO v_truck_id FROM food_trucks WHERE owner_id = p_user_id;
  IF v_truck_id IS NOT NULL THEN
    DELETE FROM event_booking_requests WHERE truck_id = v_truck_id;
    DELETE FROM truck_employees WHERE truck_id = v_truck_id;
    DELETE FROM food_trucks WHERE owner_id = p_user_id;
  END IF;

  DELETE FROM subscriptions WHERE owner_id = p_user_id;
END;
$$;

-- employee_shifts: an employee could previously PATCH clocked_in_at/clocked_out_at to
-- arbitrary values (no WITH CHECK existed on the UPDATE policy, and the INSERT policy
-- never constrained clocked_in_at either), letting them fabricate worked hours.
-- Tighten both the clock-in insert and the clock-out update to require a real-time
-- timestamp (small tolerance for clock skew/request latency) and restrict the update
-- path to only ever close a currently-open shift.

DROP POLICY IF EXISTS employee_shifts_insert_own ON public.employee_shifts;
CREATE POLICY employee_shifts_insert_own ON public.employee_shifts
  FOR INSERT
  WITH CHECK (
    auth.uid() = employee_id
    AND clocked_in_at BETWEEN now() - interval '10 minutes' AND now() + interval '10 minutes'
  );

DROP POLICY IF EXISTS employee_shifts_update_own ON public.employee_shifts;
CREATE POLICY employee_shifts_update_own ON public.employee_shifts
  FOR UPDATE
  USING (auth.uid() = employee_id AND clocked_out_at IS NULL)
  WITH CHECK (
    auth.uid() = employee_id
    AND clocked_out_at BETWEEN now() - interval '10 minutes' AND now() + interval '10 minutes'
  );

-- scheduled_shifts: employee_update_status_scheduled_shifts had a WITH CHECK, but it
-- only re-asserted auth.uid() = employee_id — it never restricted which columns could
-- change, so an employee could rewrite scheduled_start/scheduled_end/notes/truck_id on
-- their own shift, not just accept/decline its status. RLS WITH CHECK can't compare
-- against the pre-update row on its own, so this needs a trigger with real OLD/NEW
-- access. Owners (auth_user_owns_truck) are unaffected and may still edit any column.
CREATE OR REPLACE FUNCTION public.restrict_employee_scheduled_shift_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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

DROP TRIGGER IF EXISTS restrict_employee_scheduled_shift_update_trigger ON public.scheduled_shifts;
CREATE TRIGGER restrict_employee_scheduled_shift_update_trigger
  BEFORE UPDATE ON public.scheduled_shifts
  FOR EACH ROW
  EXECUTE FUNCTION public.restrict_employee_scheduled_shift_update();

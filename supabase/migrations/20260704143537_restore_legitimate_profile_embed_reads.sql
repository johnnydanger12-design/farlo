-- The self-only profiles policy just added breaks two legitimate, already-existing
-- PostgREST embedded joins (`profiles(display_name)`), which are themselves subject to
-- profiles' own RLS: OrdersRepository's order list (shows the consumer's name to the
-- truck owner/employee) and EmployeesRepository's roster/shift-history queries (shows
-- an employee's name to their truck's owner). Add narrow, relationship-scoped
-- additional SELECT policies (PERMISSIVE, OR'd with the self-only one) covering exactly
-- these two legitimate cases — not a return to the previous "anyone can read anyone".

DROP POLICY IF EXISTS "profiles: truck can read consumer on orders" ON public.profiles;
CREATE POLICY "profiles: truck can read consumer on orders" ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.consumer_id = profiles.id
        AND (auth_user_owns_truck(o.truck_id) OR auth_user_works_for_truck(o.truck_id))
    )
  );

DROP POLICY IF EXISTS "profiles: owner can read own employees" ON public.profiles;
CREATE POLICY "profiles: owner can read own employees" ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM truck_employees te
      WHERE te.user_id = profiles.id
        AND auth_user_owns_truck(te.truck_id)
    )
  );

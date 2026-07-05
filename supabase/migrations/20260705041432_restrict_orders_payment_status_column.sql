-- orders_owner_update/orders_employee_update had no WITH CHECK — an owner or
-- employee could flip payment_status directly to 'paid' via a raw PATCH with
-- no real Stripe charge behind it (security.md Consolidated Risk Register,
-- Medium: "owner/employee could flip payment_status to 'paid' without a real
-- charge"). RLS WITH CHECK can't compare against the pre-update row's other
-- columns on its own, so this needs a trigger with real OLD/NEW access, same
-- pattern as restrict_employee_scheduled_shift_update. service_role (the
-- Stripe webhook's own path) is explicitly exempted so real payment
-- confirmations still work.
CREATE OR REPLACE FUNCTION public.restrict_orders_payment_status_column()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN
    RAISE EXCEPTION 'payment_status can only be changed by the payment system' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS restrict_orders_payment_status_update_trigger ON public.orders;
CREATE TRIGGER restrict_orders_payment_status_update_trigger
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.restrict_orders_payment_status_column();

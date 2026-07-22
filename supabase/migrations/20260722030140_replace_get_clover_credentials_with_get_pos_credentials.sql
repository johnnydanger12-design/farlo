-- Generalizes get_clover_credentials (hardcoded to provider='clover') into a
-- provider-agnostic lookup the new push-order-to-pos dispatcher uses to resolve
-- whichever adapter applies to a truck.
drop function if exists public.get_clover_credentials(uuid);

create or replace function public.get_pos_credentials(p_truck_id uuid)
returns table (
  provider text,
  external_merchant_id text,
  decrypted_secret text,
  refresh_token text,
  token_expires_at timestamptz,
  clover_order_type_id text,
  clover_employee_id text,
  square_location_id text,
  environment text
)
language sql
security definer
set search_path = public
as $$
  select
    pi.provider,
    pi.external_merchant_id,
    vs.decrypted_secret,
    vr.decrypted_secret as refresh_token,
    pi.token_expires_at,
    pi.clover_order_type_id,
    pi.clover_employee_id,
    pi.square_location_id,
    pi.environment
  from pos_integrations pi
  join vault.decrypted_secrets vs on vs.name = pi.api_token_secret_name
  left join vault.decrypted_secrets vr on vr.name = pi.refresh_token_secret_name
  where pi.truck_id = p_truck_id and pi.enabled = true;
$$;

revoke all on function public.get_pos_credentials(uuid) from public;
grant execute on function public.get_pos_credentials(uuid) to service_role;

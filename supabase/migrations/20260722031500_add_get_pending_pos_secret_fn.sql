-- Used by square-select-location to decrypt a pending (not-yet-enabled)
-- integration's stored token so it can list Square locations before the
-- owner picks one. get_pos_credentials can't be reused here since it only
-- ever resolves the currently-enabled row for a truck.
create or replace function public.get_pending_pos_secret(p_truck_id uuid, p_provider text)
returns text
language sql
security definer
set search_path = public
as $$
  select vs.decrypted_secret
  from pos_integrations pi
  join vault.decrypted_secrets vs on vs.name = pi.api_token_secret_name
  where pi.truck_id = p_truck_id and pi.provider = p_provider
  limit 1;
$$;

revoke all on function public.get_pending_pos_secret(uuid, text) from public;
grant execute on function public.get_pending_pos_secret(uuid, text) to service_role;

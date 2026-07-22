-- First programmatic (non-founder-run-SQL) path to create a Vault secret in
-- this project, used by the self-serve connect-clover/connect-square functions.
create or replace function public.create_pos_secret(p_secret text, p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  v_id := vault.create_secret(p_secret, p_name);
  return v_id;
end;
$$;

revoke all on function public.create_pos_secret(text, text) from public;
grant execute on function public.create_pos_secret(text, text) to service_role;

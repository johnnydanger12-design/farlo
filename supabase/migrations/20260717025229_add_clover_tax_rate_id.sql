alter table pos_integrations add column clover_tax_rate_id text;

drop function get_clover_credentials(uuid);

create function public.get_clover_credentials(p_truck_id uuid)
 returns table(external_merchant_id text, api_token text, clover_order_type_id text, environment text, clover_employee_id text, clover_tax_rate_id text)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select pi.external_merchant_id, vs.decrypted_secret, pi.clover_order_type_id, pi.environment, pi.clover_employee_id, pi.clover_tax_rate_id
  from pos_integrations pi
  join vault.decrypted_secrets vs on vs.name = pi.api_token_secret_name
  where pi.truck_id = p_truck_id and pi.provider = 'clover' and pi.enabled = true;
$function$;

revoke all on function public.get_clover_credentials(uuid) from public, anon, authenticated;
grant execute on function public.get_clover_credentials(uuid) to service_role;

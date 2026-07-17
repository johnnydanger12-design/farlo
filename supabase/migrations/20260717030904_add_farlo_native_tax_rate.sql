alter table food_trucks add column tax_rate_percent numeric;
comment on column food_trucks.tax_rate_percent is 'Owner-entered sales tax percent (e.g. 8.5 for 8.5%), applied on top of item subtotal at checkout. Null/0 = no tax charged.';

alter table orders add column tax_price numeric not null default 0;
comment on column orders.tax_price is 'Tax actually charged via Stripe for this order, computed server-side in create-payment-intent at order time from the truck''s tax_rate_percent — stored so order totals and any downstream POS ticket stay consistent with what was really charged.';

-- Cleanup: the abandoned approach of referencing a Clover-side tax rate object
-- per integration. Businesses set their own tax rate in Farlo instead (above).
drop function get_clover_credentials(uuid);
alter table pos_integrations drop column clover_tax_rate_id;

create function public.get_clover_credentials(p_truck_id uuid)
 returns table(external_merchant_id text, api_token text, clover_order_type_id text, environment text, clover_employee_id text)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select pi.external_merchant_id, vs.decrypted_secret, pi.clover_order_type_id, pi.environment, pi.clover_employee_id
  from pos_integrations pi
  join vault.decrypted_secrets vs on vs.name = pi.api_token_secret_name
  where pi.truck_id = p_truck_id and pi.provider = 'clover' and pi.enabled = true;
$function$;

revoke all on function public.get_clover_credentials(uuid) from public, anon, authenticated;
grant execute on function public.get_clover_credentials(uuid) to service_role;

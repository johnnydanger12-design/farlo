create or replace function public.push_order_to_clover()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_should_fire boolean;
  v_bearer text;
begin
  select exists(
    select 1 from pos_integrations
    where truck_id = new.truck_id and provider = 'clover' and enabled = true
  ) or exists(
    select 1 from food_trucks
    where id = new.truck_id
      and (auto_accept_orders or auto_mark_ready or auto_mark_complete)
  ) into v_should_fire;

  if not v_should_fire then
    return new;
  end if;

  select decrypted_secret into v_bearer from vault.decrypted_secrets where name = 'agent_cron_bearer';

  perform net.http_post(
    url := 'https://weflrxyerxpsafcdetya.supabase.co/functions/v1/push-order-to-clover',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_bearer, 'Content-Type', 'application/json'),
    body := jsonb_build_object('order_id', new.id)
  );

  return new;
end;
$function$;

-- push-order-to-clover is being renamed/rewritten as push-order-to-pos (a real
-- multi-provider dispatcher, not Clover-specific). Fire on any enabled provider,
-- not just clover, and point at the renamed function's URL.
create or replace function public.push_order_to_pos()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_should_fire boolean;
  v_bearer text;
begin
  select exists(
    select 1 from pos_integrations
    where truck_id = new.truck_id and enabled = true
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
    url := 'https://weflrxyerxpsafcdetya.supabase.co/functions/v1/push-order-to-pos',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_bearer, 'Content-Type', 'application/json'),
    body := jsonb_build_object('order_id', new.id)
  );

  return new;
end;
$$;

drop trigger push_order_to_clover_trigger on orders;

create trigger push_order_to_pos_trigger
  after insert on orders
  for each row
  execute function public.push_order_to_pos();

drop function public.push_order_to_clover();

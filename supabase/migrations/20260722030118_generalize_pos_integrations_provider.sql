-- Widen provider CHECK to admit square, enforce single-enabled-provider-per-truck,
-- and add real owner-facing RLS (previously zero policies existed; the table was
-- service_role-only). Column-scoped grant lets an owner flip enabled/disabled
-- directly; every other column (merchant id, secret names, employee id) stays
-- writable only through service-role edge functions.

alter table public.pos_integrations
  drop constraint pos_integrations_provider_check;
alter table public.pos_integrations
  add constraint pos_integrations_provider_check
  check (provider = any (array['clover'::text, 'square'::text]));

create unique index pos_integrations_truck_enabled_idx
  on public.pos_integrations (truck_id)
  where enabled;

revoke all on public.pos_integrations from anon;
revoke all on public.pos_integrations from authenticated;
grant select on public.pos_integrations to authenticated;
grant update (enabled) on public.pos_integrations to authenticated;

create policy "Owners can view their pos integration"
  on public.pos_integrations for select
  to authenticated
  using (exists (
    select 1 from public.food_trucks ft
    where ft.id = pos_integrations.truck_id and ft.owner_id = auth.uid()
  ));

create policy "Owners can toggle their pos integration enabled state"
  on public.pos_integrations for update
  to authenticated
  using (exists (
    select 1 from public.food_trucks ft
    where ft.id = pos_integrations.truck_id and ft.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.food_trucks ft
    where ft.id = pos_integrations.truck_id and ft.owner_id = auth.uid()
  ));

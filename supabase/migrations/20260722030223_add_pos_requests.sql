-- Lightweight capture for "request a POS we don't support yet" from the
-- self-serve POS hub screen. SQL-only checking for now, no dashboard view.
create table public.pos_requests (
  id uuid primary key default gen_random_uuid(),
  truck_id uuid not null references public.food_trucks(id) on delete cascade,
  requested_provider text not null,
  note text,
  created_at timestamptz not null default now()
);

alter table public.pos_requests enable row level security;

revoke all on public.pos_requests from anon;
revoke all on public.pos_requests from authenticated;
grant insert on public.pos_requests to authenticated;

create policy "Owners can request a pos integration"
  on public.pos_requests for insert
  to authenticated
  with check (exists (
    select 1 from public.food_trucks ft
    where ft.id = pos_requests.truck_id and ft.owner_id = auth.uid()
  ));

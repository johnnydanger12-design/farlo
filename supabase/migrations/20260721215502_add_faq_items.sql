create table faq_items (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  question text not null,
  answer text not null,
  sort_order integer not null default 0,
  category_sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
comment on table faq_items is 'Founder-maintained FAQ content shown in-app (Settings > Help). No owner-facing editor — content is authored/edited directly via SQL, same as other founder-controlled content in this project.';

alter table faq_items enable row level security;

create policy "Anyone can view FAQ items"
  on faq_items for select
  using (true);

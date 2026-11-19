-- Run once if you already ran schema.sql before Nov 19, 2026: adds saved tree positions.
create table if not exists public.tree_locations (
  tree_key   text primary key,
  lat        double precision not null,
  lng        double precision not null,
  updated_by text,
  updated_at timestamptz not null default now()
);
alter table public.tree_locations enable row level security;
drop policy if exists "signed in: all" on public.tree_locations;
create policy "signed in: all" on public.tree_locations for all to authenticated using (true) with check (true);

-- CDOT Arborist Reports — Supabase schema
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.

-- One row per monthly report per region (re-importing the same region + month replaces it)
create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  region      text not null check (region in ('north','southwest','central','southeast')),
  month       text not null check (month ~ '^\d{4}-\d{2}$'),   -- 'YYYY-MM'
  contractor  text,
  file_name   text,
  tree_count  int,
  sites       jsonb,          -- [{site, title, siteType, inspection, count}]
  warnings    jsonb,
  uploaded_by uuid default auth.uid() references auth.users(id),
  uploaded_at timestamptz not null default now(),
  unique (region, month)
);

-- Every tree row in a report. tree_key is location-based (region|site|planter|tree no.|address)
-- so the same tree lines up across months for history.
create table if not exists public.report_trees (
  report_id uuid not null references public.reports(id) on delete cascade,
  tree_key  text not null,
  site      text,
  data      jsonb not null,
  primary key (report_id, tree_key)
);
create index if not exists report_trees_key_idx on public.report_trees (tree_key);

-- Your own notes on a tree; follow_up marks it for attention until resolved
create table if not exists public.tree_notes (
  id           uuid primary key default gen_random_uuid(),
  tree_key     text not null,
  body         text not null,
  follow_up    boolean not null default false,
  resolved     boolean not null default false,
  author_email text,
  created_by   uuid default auth.uid() references auth.users(id),
  created_at   timestamptz not null default now()
);
create index if not exists tree_notes_key_idx on public.tree_notes (tree_key);

-- Only signed-in users can read or write anything
alter table public.reports      enable row level security;
alter table public.report_trees enable row level security;
alter table public.tree_notes   enable row level security;

drop policy if exists "signed in: all" on public.reports;
drop policy if exists "signed in: all" on public.report_trees;
drop policy if exists "signed in: all" on public.tree_notes;
create policy "signed in: all" on public.reports      for all to authenticated using (true) with check (true);
create policy "signed in: all" on public.report_trees for all to authenticated using (true) with check (true);
create policy "signed in: all" on public.tree_notes   for all to authenticated using (true) with check (true);

-- Hand-adjusted tree positions (drag the pin in the app). Keyed by tree, so they carry across months.
create table if not exists public.tree_locations (
  tree_key   text primary key,
  lat        double precision not null,
  lng        double precision not null,
  updated_by text,
  updated_at timestamptz not null default now(),
  source     text,               -- 'gps' or 'map'
  accuracy_m double precision    -- GPS accuracy in meters
);
alter table public.tree_locations enable row level security;
drop policy if exists "signed in: all" on public.tree_locations;
create policy "signed in: all" on public.tree_locations for all to authenticated using (true) with check (true);

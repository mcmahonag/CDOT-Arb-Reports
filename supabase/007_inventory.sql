-- 007: new GPS tree inventory, collected tree by tree in the field.
-- Run once after 006.

create table if not exists public.inventory_trees (
  id            uuid primary key default gen_random_uuid(),
  region        text not null check (region in ('north', 'southwest', 'central', 'southeast')),
  site          text not null,
  planter       text,
  position      text,                    -- tree number within the site / planter
  tree_uid      text,                    -- permanent ID (linked old record, or new)
  linked        boolean not null default false,  -- true when tree_uid came from an old record
  status        text not null default 'tree' check (status in ('tree', 'vacant', 'not_found')),
  lat           double precision,
  lng           double precision,
  accuracy_m    double precision,
  loc_source    text,                    -- 'gps' or 'map' (nudged)
  genus         text,
  species       text,
  cultivar      text,
  dbh           numeric,
  condition     text check (condition in ('good', 'fair', 'poor', 'dead') or condition is null),
  pests         text,
  deadwood      numeric,
  hazard        int,
  comments      text,
  address       text,                    -- nearest street address worked out from the centerline
  addr_dir      text,
  street        text,
  photo_path    text,
  collected_by  text,
  collected_at  timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists inventory_region_site_idx on public.inventory_trees (region, site);
create unique index if not exists inventory_uid_idx on public.inventory_trees (tree_uid) where tree_uid is not null;

alter table public.inventory_trees enable row level security;
drop policy if exists "inventory read" on public.inventory_trees;
drop policy if exists "inventory write" on public.inventory_trees;
create policy "inventory read" on public.inventory_trees for select to authenticated using (public.can_region(region));
create policy "inventory write" on public.inventory_trees for all to authenticated
  using (public.can_region(region)) with check (public.can_region(region));

-- Inventory reports can share a month with a field report
alter table public.reports drop constraint if exists reports_region_month_key;
create unique index if not exists reports_region_month_source_idx on public.reports (region, month, source);

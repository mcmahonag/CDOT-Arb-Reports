-- 009: unit prices to 4 decimals, and regions no longer hard-coded in the database.
-- Run once in the Supabase SQL Editor, after 008. Safe to run again.
--
-- 1) Some contract unit prices have more than 2 decimals (e.g. $19.0962 / each, $0.2 / sq yd).
--    Proposal line amounts and totals are still rounded to the cent.
alter table public.price_items alter column unit_price type numeric(12, 4);

-- 2) Drop the fixed region lists (north/southwest/central/southeast) so a new region
--    such as Lake Shore Drive only needs adding to REGIONS in config.js.
do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname
    from pg_constraint c
    join pg_namespace n on n.oid = c.connamespace
    where n.nspname = 'public' and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%region%southwest%'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
  end loop;
end $$;

-- Region ids must still be short lowercase codes (e.g. 'lsd_north').
do $$
declare t text;
begin
  foreach t in array array['reports', 'inventory_trees', 'price_items', 'proposals'] loop
    if to_regclass('public.' || t) is not null and not exists (
      select 1 from pg_constraint where conrelid = ('public.' || t)::regclass and conname = t || '_region_fmt') then
      execute format('alter table public.%I add constraint %I check (region ~ ''^[a-z][a-z0-9_]{1,30}$'')', t, t || '_region_fmt');
    end if;
  end loop;
end $$;

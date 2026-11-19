-- 006: permanent tree IDs (T-10001, T-10002, ...)
-- Run once after 005. Gives every tree already in the database an ID, then moves saved
-- locations, notes, photos and work orders onto those IDs so they survive renumbering.

create sequence if not exists public.tree_uid_seq start 10001;

create table if not exists public.trees (
  uid          text primary key default ('T-' || nextval('public.tree_uid_seq')),
  region       text not null,
  site         text,
  current_key  text,              -- latest location key (region|site|planter|no|address)
  merged_into  text,              -- set when this ID was merged into another
  created_by   text,
  created_at   timestamptz not null default now()
);
create unique index if not exists trees_current_key_idx on public.trees (current_key) where merged_into is null;
create index if not exists trees_region_idx on public.trees (region);

alter table public.report_trees add column if not exists tree_uid text;
create index if not exists report_trees_uid_idx on public.report_trees (tree_uid);

-- Region of a tree key: old location keys start with the region; IDs are looked up
create or replace function public.tree_region(k text) returns text
  language sql stable security definer set search_path = public
  as $$ select case when position('|' in k) > 0 then split_part(k, '|', 1)
                    else (select region from public.trees where uid = k) end $$;

-- ---------- Backfill: one ID per tree, numbered in site order ----------
insert into public.trees (region, site, current_key)
select region, site, tree_key from (
  select distinct on (rt.tree_key) rt.tree_key, rp.region, rt.site,
         coalesce((rt.data->>'seq')::int, 0) as seq, rp.month
  from public.report_trees rt join public.reports rp on rp.id = rt.report_id
  where rt.tree_uid is null
    and not exists (select 1 from public.trees t where t.current_key = rt.tree_key)
  order by rt.tree_key, rp.month desc
) x
order by region, site, seq, tree_key;

update public.report_trees rt set tree_uid = t.uid
  from public.trees t where rt.tree_uid is null and t.current_key = rt.tree_key;

-- ---------- Move side tables onto IDs ----------
update public.tree_locations l set tree_key = t.uid from public.trees t
  where l.tree_key = t.current_key and not exists (select 1 from public.tree_locations x where x.tree_key = t.uid);
update public.tree_notes n  set tree_key = t.uid from public.trees t where n.tree_key = t.current_key;
update public.tree_photos p set tree_key = t.uid from public.trees t where p.tree_key = t.current_key;

-- work_orders.region was computed from the key; make it a normal column filled by a trigger
alter table public.work_orders add column if not exists region_new text;
update public.work_orders set region_new = region where region_new is null;
alter table public.work_orders drop column if exists region cascade;
alter table public.work_orders rename column region_new to region;
create index if not exists work_orders_region_status_idx on public.work_orders (region, status);
update public.work_orders w set tree_key = t.uid from public.trees t where w.tree_key = t.current_key;
update public.work_orders set region = public.tree_region(tree_key) where region is null;

create or replace function public.work_order_region() returns trigger
  language plpgsql security definer set search_path = public
  as $$ begin new.region := coalesce(new.region, public.tree_region(new.tree_key)); return new; end $$;
drop trigger if exists work_orders_region on public.work_orders;
create trigger work_orders_region before insert on public.work_orders for each row execute function public.work_order_region();

-- ---------- Policies use the tree's region ----------
alter table public.trees enable row level security;
drop policy if exists "trees ids read" on public.trees;
drop policy if exists "trees ids add" on public.trees;
drop policy if exists "trees ids update" on public.trees;
create policy "trees ids read" on public.trees for select to authenticated using (public.can_region(region));
create policy "trees ids add" on public.trees for insert to authenticated with check (public.can_region(region));
create policy "trees ids update" on public.trees for update to authenticated using (public.can_region(region)) with check (public.can_region(region));
grant usage on sequence public.tree_uid_seq to authenticated;

drop policy if exists "locations read" on public.tree_locations;
drop policy if exists "locations write" on public.tree_locations;
create policy "locations read" on public.tree_locations for select to authenticated using (public.can_region(public.tree_region(tree_key)));
create policy "locations write" on public.tree_locations for all to authenticated
  using (public.can_region(public.tree_region(tree_key))) with check (public.can_region(public.tree_region(tree_key)));

drop policy if exists "photos read" on public.tree_photos;
drop policy if exists "photos add" on public.tree_photos;
create policy "photos read" on public.tree_photos for select to authenticated using (public.can_region(public.tree_region(tree_key)));
create policy "photos add" on public.tree_photos for insert to authenticated with check (public.can_region(public.tree_region(tree_key)));

drop policy if exists "orders read" on public.work_orders;
create policy "orders read" on public.work_orders for select to authenticated using (public.can_region(region));

-- ---------- Completing a work order finds the tree by ID ----------
create or replace function public.complete_work_order(order_id uuid, done_on date, notes text)
  returns uuid
  language plpgsql security definer set search_path = public
as $$
declare
  o public.work_orders;
  rep uuid;
  rkey text;
  ym text := to_char(done_on, 'YYYY-MM');
  label text := trim(to_char(done_on, 'YYYY Month'));
  who text := (select email from public.profiles where user_id = auth.uid());
  patch jsonb;
begin
  select * into o from public.work_orders where id = order_id for update;
  if o.id is null then raise exception 'Work order not found'; end if;
  if not public.can_region(o.region) then raise exception 'Not allowed for this region'; end if;
  if o.status <> 'open' then raise exception 'This work order is already %', o.status; end if;

  select r.id, t.tree_key into rep, rkey from public.reports r
    join public.report_trees t on t.report_id = r.id and (t.tree_uid = o.tree_key or t.tree_key = o.tree_key)
    where r.region = o.region order by r.month desc, r.uploaded_at desc limit 1;

  patch := case o.type
    when 'prune'  then jsonb_build_object('pruned', label, 'prunedYM', ym)
    when 'remove' then jsonb_build_object('status', 'removed', 'removed', label, 'reason', coalesce(nullif(o.event, ''), nullif(o.details, ''), 'Work order'))
    when 'treat'  then jsonb_build_object('treated', label)
    else '{}'::jsonb end
    || jsonb_build_object('lastWork', jsonb_build_object('type', o.type, 'on', done_on, 'by', who, 'notes', notes));

  if rep is not null then
    update public.report_trees set data = data || patch, edited_by = who, edited_at = now()
      where report_id = rep and tree_key = rkey;
  end if;

  update public.work_orders set status = 'completed', completed_by = who, completed_at = now(),
    completed_on = done_on, completion_notes = notes, applied_report = rep
    where id = order_id;
  return rep;
end $$;

-- ---------- Merge two IDs that are the same tree (staff) ----------
create or replace function public.merge_trees(from_uid text, into_uid text) returns void
  language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_staff() then raise exception 'Staff only'; end if;
  if from_uid = into_uid then raise exception 'Pick a different tree'; end if;
  if not exists (select 1 from public.trees where uid = into_uid and merged_into is null) then raise exception 'Tree % not found', into_uid; end if;
  update public.report_trees set tree_uid = into_uid where tree_uid = from_uid;
  update public.tree_notes set tree_key = into_uid where tree_key = from_uid;
  update public.tree_photos set tree_key = into_uid where tree_key = from_uid;
  update public.work_orders set tree_key = into_uid where tree_key = from_uid;
  -- keep the surviving tree's saved location if it has one
  if exists (select 1 from public.tree_locations where tree_key = into_uid) then
    delete from public.tree_locations where tree_key = from_uid;
  else
    update public.tree_locations set tree_key = into_uid where tree_key = from_uid;
  end if;
  update public.trees set merged_into = into_uid, current_key = null where uid = from_uid;
end $$;

-- ---------- Give one report row a new ID (it was wrongly matched) (staff) ----------
create or replace function public.split_tree(rep_id uuid, key text) returns text
  language plpgsql security definer set search_path = public
as $$
declare nu text; reg text;
begin
  if not public.is_staff() then raise exception 'Staff only'; end if;
  select region into reg from public.reports where id = rep_id;
  insert into public.trees (region, site, current_key)
    select reg, site, null from public.report_trees where report_id = rep_id and tree_key = key
    returning uid into nu;
  update public.trees set current_key = null where current_key = key;
  update public.trees set current_key = key where uid = nu;
  update public.report_trees set tree_uid = nu, data = data - 'uidMatch' where report_id = rep_id and tree_key = key;
  return nu;
end $$;

grant execute on function public.merge_trees(text, text) to authenticated;
grant execute on function public.split_tree(uuid, text) to authenticated;

-- 005: work orders (prune / remove / treat / inspect) issued by staff, completed by contractors.
-- Run once after 004. Completing an order updates the tree in that region's latest report.

create table if not exists public.work_orders (
  id               uuid primary key default gen_random_uuid(),
  tree_key         text not null,
  region           text generated always as (split_part(tree_key, '|', 1)) stored,
  site             text,
  tree_label       text,                 -- e.g. "Tilia cordata #3 · 1608 N Ashland Ave", for lists
  type             text not null check (type in ('prune', 'remove', 'treat', 'inspect', 'other')),
  priority         text not null default 'routine' check (priority in ('routine', 'urgent')),
  due_date         date,
  details          text,
  event            text,                 -- storm or event name, e.g. "Nov 18 windstorm"
  status           text not null default 'open' check (status in ('open', 'completed', 'cancelled')),
  created_by       text,
  created_at       timestamptz not null default now(),
  completed_by     text,
  completed_at     timestamptz,
  completed_on     date,                 -- the day the work was done
  completion_notes text,
  applied_report   uuid                  -- report whose tree record was updated
);
create index if not exists work_orders_region_status_idx on public.work_orders (region, status);
create index if not exists work_orders_key_idx on public.work_orders (tree_key);

alter table public.work_orders enable row level security;
drop policy if exists "orders read" on public.work_orders;
drop policy if exists "orders staff" on public.work_orders;
create policy "orders read" on public.work_orders for select to authenticated using (public.can_region(region));
create policy "orders staff" on public.work_orders for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Contractors (and staff) complete an order through this function, which also updates the arborist report.
create or replace function public.complete_work_order(order_id uuid, done_on date, notes text)
  returns uuid
  language plpgsql security definer set search_path = public
as $$
declare
  o public.work_orders;
  rep uuid;
  ym text := to_char(done_on, 'YYYY-MM');
  label text := trim(to_char(done_on, 'YYYY Month'));
  who text := (select email from public.profiles where user_id = auth.uid());
  patch jsonb;
begin
  select * into o from public.work_orders where id = order_id for update;
  if o.id is null then raise exception 'Work order not found'; end if;
  if not public.can_region(o.region) then raise exception 'Not allowed for this region'; end if;
  if o.status <> 'open' then raise exception 'This work order is already %', o.status; end if;

  -- latest report for the region that has this tree
  select r.id into rep from public.reports r
    join public.report_trees t on t.report_id = r.id and t.tree_key = o.tree_key
    where r.region = o.region order by r.month desc, r.uploaded_at desc limit 1;

  patch := case o.type
    when 'prune'  then jsonb_build_object('pruned', label, 'prunedYM', ym)
    when 'remove' then jsonb_build_object('status', 'removed', 'removed', label, 'reason', coalesce(nullif(o.event, ''), nullif(o.details, ''), 'Work order'))
    when 'treat'  then jsonb_build_object('treated', label)
    else '{}'::jsonb end
    || jsonb_build_object('lastWork', jsonb_build_object('type', o.type, 'on', done_on, 'by', who, 'notes', notes));

  if rep is not null then
    update public.report_trees set data = data || patch, edited_by = who, edited_at = now()
      where report_id = rep and tree_key = o.tree_key;
  end if;

  update public.work_orders set status = 'completed', completed_by = who, completed_at = now(),
    completed_on = done_on, completion_notes = notes, applied_report = rep
    where id = order_id;
  return rep;
end $$;
grant execute on function public.complete_work_order(uuid, date, text) to authenticated;

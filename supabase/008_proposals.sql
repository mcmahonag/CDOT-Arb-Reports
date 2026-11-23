-- 008: contract price sheets and contractor proposals (contractor -> CDOT, priced from the contract)
-- Run once after 007.

-- ---------- Contract unit prices, one sheet per region ----------
create table if not exists public.price_items (
  id          uuid primary key default gen_random_uuid(),
  region      text not null check (region in ('north', 'southwest', 'central', 'southeast')),
  item_no     text,
  description text not null,
  unit        text,
  unit_price  numeric(12, 2) not null,
  sheet       text,               -- e.g. "2026 Southwest landscape contract"
  effective   date,
  active      boolean not null default true,
  sort        int,
  created_at  timestamptz not null default now()
);
create index if not exists price_items_region_idx on public.price_items (region, active);
alter table public.price_items enable row level security;
drop policy if exists "prices read" on public.price_items;
drop policy if exists "prices staff" on public.price_items;
create policy "prices read" on public.price_items for select to authenticated using (public.can_region(region));
create policy "prices staff" on public.price_items for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- ---------- Proposals ----------
create sequence if not exists public.proposal_seq start 1001;
grant usage on sequence public.proposal_seq to authenticated;

create table if not exists public.proposals (
  id             uuid primary key default gen_random_uuid(),
  number         text not null default ('P-' || nextval('public.proposal_seq')),
  region         text not null check (region in ('north', 'southwest', 'central', 'southeast')),
  contractor     text,
  service        text not null default 'treat' check (service in ('treat', 'prune', 'remove', 'plant', 'other')),
  priority       text not null default 'routine' check (priority in ('routine', 'urgent')),
  title          text not null,
  issue          text,             -- what the contractor found
  recommendation text,             -- what they propose
  trees          jsonb not null default '[]',   -- [{key, label, site, dbh}]
  sites          text[],
  lines          jsonb not null default '[]',   -- [{item_id?, item_no, description, unit, unit_price, qty, amount, note}]
  total          numeric(12, 2) not null default 0,
  photos         text[] not null default '{}',  -- storage paths in tree-photos
  messages       jsonb not null default '[]',   -- [{by, role, at, text}]
  status         text not null default 'submitted' check (status in ('submitted', 'questions', 'approved', 'declined', 'withdrawn')),
  submitted_by   text,
  submitted_at   timestamptz not null default now(),
  decided_by     text,
  decided_at     timestamptz,
  decision_note  text,
  updated_at     timestamptz not null default now()
);
create unique index if not exists proposals_number_idx on public.proposals (number);
create index if not exists proposals_region_status_idx on public.proposals (region, status);

-- Contract lines always use the contract unit price; amounts and the total are recomputed here,
-- so a proposal can't carry prices that differ from the sheet.
create or replace function public.price_proposal() returns trigger
  language plpgsql security definer set search_path = public
as $$
begin
  select coalesce(jsonb_agg(
           case when p.id is not null then
             l || jsonb_build_object('unit_price', p.unit_price, 'item_no', p.item_no, 'description', p.description, 'unit', p.unit,
                                     'amount', round(coalesce(nullif(l->>'qty', '')::numeric, 0) * p.unit_price, 2))
           else
             l || jsonb_build_object('amount', round(coalesce(nullif(l->>'qty', '')::numeric, 0) * coalesce(nullif(l->>'unit_price', '')::numeric, 0), 2), 'item_id', null)
           end order by x.ord), '[]'::jsonb)
    into new.lines
    from jsonb_array_elements(coalesce(new.lines, '[]'::jsonb)) with ordinality as x(l, ord)
    left join public.price_items p on p.id::text = x.l->>'item_id' and p.region = new.region;
  select coalesce(sum((l->>'amount')::numeric), 0) into new.total from jsonb_array_elements(new.lines) l;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists proposals_price on public.proposals;
create trigger proposals_price before insert or update of lines, region on public.proposals
  for each row execute function public.price_proposal();

alter table public.proposals enable row level security;
drop policy if exists "proposals read" on public.proposals;
drop policy if exists "proposals add" on public.proposals;
drop policy if exists "proposals update" on public.proposals;
drop policy if exists "proposals delete" on public.proposals;
create policy "proposals read" on public.proposals for select to authenticated using (public.can_region(region));
create policy "proposals add" on public.proposals for insert to authenticated
  with check (public.can_region(region) and status = 'submitted');
-- contractors can edit, answer questions on, or withdraw their open proposals; staff decide
create policy "proposals update" on public.proposals for update to authenticated
  using (public.is_staff() or (public.can_region(region) and status in ('submitted', 'questions')))
  with check (public.is_staff() or (public.can_region(region) and status in ('submitted', 'questions', 'withdrawn')));
create policy "proposals delete" on public.proposals for delete to authenticated using (public.is_staff());

-- Work orders created from an approved proposal point back to it
alter table public.work_orders add column if not exists proposal_id uuid references public.proposals(id) on delete set null;

-- 004: staff / contractor roles, region-based access, field reports, photos
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.
-- Everyone who already has a login becomes staff. New logins start as "pending" (no access)
-- until a staff member assigns a role on the app's People screen.

-- ---------- Roles ----------
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  role       text not null default 'pending' check (role in ('pending', 'staff', 'contractor')),
  contractor text,                          -- company name shown in the app
  regions    text[] not null default '{}',  -- regions a contractor can see and edit
  created_at timestamptz not null default now()
);

create or replace function public.my_role() returns text
  language sql stable security definer set search_path = public
  as $$ select role from public.profiles where user_id = auth.uid() $$;

create or replace function public.is_staff() returns boolean
  language sql stable security definer set search_path = public
  as $$ select coalesce((select role = 'staff' from public.profiles where user_id = auth.uid()), false) $$;

create or replace function public.can_region(r text) returns boolean
  language sql stable security definer set search_path = public
  as $$ select public.is_staff() or exists (
           select 1 from public.profiles
           where user_id = auth.uid() and role = 'contractor' and r = any(regions)) $$;

-- New logins get a pending profile automatically
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer set search_path = public
  as $$ begin
    insert into public.profiles (user_id, email) values (new.id, new.email) on conflict (user_id) do nothing;
    return new;
  end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Existing logins become staff
insert into public.profiles (user_id, email, role)
  select id, email, 'staff' from auth.users
  on conflict (user_id) do nothing;

alter table public.profiles enable row level security;
drop policy if exists "read own or staff" on public.profiles;
drop policy if exists "staff manage" on public.profiles;
create policy "read own or staff" on public.profiles for select to authenticated using (user_id = auth.uid() or public.is_staff());
create policy "staff manage" on public.profiles for update to authenticated using (public.is_staff()) with check (public.is_staff());

-- ---------- Reports: field drafts ----------
alter table public.reports add column if not exists status text not null default 'final';
alter table public.reports add column if not exists source text not null default 'excel';
alter table public.reports add column if not exists submitted_by text;
alter table public.reports add column if not exists submitted_at timestamptz;
do $$ begin
  alter table public.reports add constraint reports_status_chk check (status in ('draft', 'submitted', 'final'));
exception when duplicate_object then null; end $$;

alter table public.report_trees add column if not exists edited_by text;
alter table public.report_trees add column if not exists edited_at timestamptz;

-- Replace the old "any signed-in user" policies with role/region rules
drop policy if exists "signed in: all" on public.reports;
drop policy if exists "signed in: all" on public.report_trees;
drop policy if exists "signed in: all" on public.tree_notes;
drop policy if exists "signed in: all" on public.tree_locations;
drop policy if exists "reports read" on public.reports;
drop policy if exists "reports insert" on public.reports;
drop policy if exists "reports update" on public.reports;
drop policy if exists "reports delete" on public.reports;
drop policy if exists "trees read" on public.report_trees;
drop policy if exists "trees write" on public.report_trees;
drop policy if exists "notes staff" on public.tree_notes;
drop policy if exists "locations read" on public.tree_locations;
drop policy if exists "locations write" on public.tree_locations;

create policy "reports read" on public.reports for select to authenticated
  using (public.can_region(region));
create policy "reports insert" on public.reports for insert to authenticated
  with check (public.is_staff() or (public.can_region(region) and status = 'draft' and source = 'field'));
-- contractors can edit (and submit) only their own drafts; staff can change anything, including reopening
create policy "reports update" on public.reports for update to authenticated
  using (public.is_staff() or (public.can_region(region) and status = 'draft'))
  with check (public.is_staff() or (public.can_region(region) and status in ('draft', 'submitted')));
create policy "reports delete" on public.reports for delete to authenticated
  using (public.is_staff() or (public.can_region(region) and status = 'draft'));

create policy "trees read" on public.report_trees for select to authenticated
  using (exists (select 1 from public.reports r where r.id = report_id and public.can_region(r.region)));
create policy "trees write" on public.report_trees for all to authenticated
  using (exists (select 1 from public.reports r where r.id = report_id
                 and (public.is_staff() or (public.can_region(r.region) and r.status = 'draft'))))
  with check (exists (select 1 from public.reports r where r.id = report_id
                 and (public.is_staff() or (public.can_region(r.region) and r.status = 'draft'))));

-- Notes and follow-ups are staff-only
create policy "notes staff" on public.tree_notes for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- Saved locations: tree_key starts with the region ("north|site|...")
create policy "locations read" on public.tree_locations for select to authenticated
  using (public.can_region(split_part(tree_key, '|', 1)));
create policy "locations write" on public.tree_locations for all to authenticated
  using (public.can_region(split_part(tree_key, '|', 1)))
  with check (public.can_region(split_part(tree_key, '|', 1)));

-- ---------- Photos ----------
create table if not exists public.tree_photos (
  id           uuid primary key default gen_random_uuid(),
  tree_key     text not null,
  report_id    uuid references public.reports(id) on delete set null,
  path         text not null,          -- storage path in the tree-photos bucket: <region>/<uuid>.jpg
  caption      text,
  author_email text,
  created_by   uuid default auth.uid() references auth.users(id),
  created_at   timestamptz not null default now()
);
create index if not exists tree_photos_key_idx on public.tree_photos (tree_key);
alter table public.tree_photos enable row level security;
drop policy if exists "photos read" on public.tree_photos;
drop policy if exists "photos add" on public.tree_photos;
drop policy if exists "photos delete" on public.tree_photos;
create policy "photos read" on public.tree_photos for select to authenticated
  using (public.can_region(split_part(tree_key, '|', 1)));
create policy "photos add" on public.tree_photos for insert to authenticated
  with check (public.can_region(split_part(tree_key, '|', 1)));
create policy "photos delete" on public.tree_photos for delete to authenticated
  using (public.is_staff() or created_by = auth.uid());

-- Private storage bucket; files live under a folder named for the region
insert into storage.buckets (id, name, public) values ('tree-photos', 'tree-photos', false)
  on conflict (id) do nothing;
drop policy if exists "tree photos read" on storage.objects;
drop policy if exists "tree photos add" on storage.objects;
drop policy if exists "tree photos delete" on storage.objects;
create policy "tree photos read" on storage.objects for select to authenticated
  using (bucket_id = 'tree-photos' and public.can_region((storage.foldername(name))[1]));
create policy "tree photos add" on storage.objects for insert to authenticated
  with check (bucket_id = 'tree-photos' and public.can_region((storage.foldername(name))[1]));
create policy "tree photos delete" on storage.objects for delete to authenticated
  using (bucket_id = 'tree-photos' and (public.is_staff() or owner = auth.uid()));

-- Run once: records whether a saved tree location came from GPS or a map drag, and the GPS accuracy.
alter table public.tree_locations add column if not exists source text;
alter table public.tree_locations add column if not exists accuracy_m double precision;

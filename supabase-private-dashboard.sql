-- PRIVATE BIRTHDAY MANAGEMENT TABLES
-- Run in Supabase Dashboard -> SQL Editor using the postgres role.
-- These views are NOT part of the public invitation and require database-admin access.
-- Never grant anon, authenticated or service_role permission to these views.
-- If your Sidequest update isn't applied yet, run supabase-sidequest-upgrade.sql first.
--
-- ON = overnight (includes guests doing both)
-- OD = daytime (includes guests doing both)
-- Guest totals exclude Maybe/No. A person doing both still counts only once as Coming.
-- Switch/Xbox/PS columns count guests who selected a MODEL, not the
-- number of devices of that model (the RSVP only records total consoles).

begin;

create schema if not exists bday_admin;

-- Keep this schema private even when the website's public API is enabled.
revoke all on schema bday_admin from public, anon, authenticated, service_role;

-- A single-row live management overview.
create or replace view bday_admin.summary as
select
  count(*) filter (where attendance = 'yes')::integer as "Total coming",
  count(*) filter (where attendance = 'maybe')::integer as "Maybe",
  count(*) filter (where attendance = 'no')::integer as "Can't come",
  count(*) filter (where attendance = 'yes' and visit_mode in ('overnight','both'))::integer as "ON (overnight)",
  count(*) filter (where attendance = 'yes' and visit_mode in ('day','both'))::integer as "OD (daytime)",
  count(*) filter (where attendance = 'yes' and visit_mode = 'both')::integer as "Both",
  count(*) filter (where attendance = 'yes' and visit_mode = 'overnight')::integer as "Overnight only",
  count(*) filter (where attendance = 'yes' and visit_mode = 'day')::integer as "Day only",
  count(*) filter (where attendance = 'yes' and visit_mode = 'unsure')::integer as "Undecided",
  coalesce(sum(pcs) filter (where attendance = 'yes'),0)::integer as "PCs",
  coalesce(sum(consoles) filter (where attendance = 'yes'),0)::integer as "Consoles total",
  count(*) filter (where attendance = 'yes' and 'Nintendo Switch 1' = any(console_types))::integer as "Switch 1",
  count(*) filter (where attendance = 'yes' and 'Nintendo Switch 2' = any(console_types))::integer as "Switch 2",
  count(*) filter (where attendance = 'yes' and 'Xbox' = any(console_types))::integer as "Xbox",
  count(*) filter (where attendance = 'yes' and 'PlayStation 4' = any(console_types))::integer as "PS4",
  count(*) filter (where attendance = 'yes' and 'PlayStation 5' = any(console_types))::integer as "PS5",
  count(*) filter (where attendance = 'yes' and 'Other' = any(console_types))::integer as "Other console",
  coalesce(sum(monitors + tvs) filter (where attendance = 'yes'),0)::integer as "Screens",
  count(*) filter (where attendance = 'yes' and sidequest_interest = 'yes')::integer as "Sidequest yes",
  count(*) filter (where attendance = 'yes' and sidequest_interest = 'maybe')::integer as "Sidequest maybe"
from public.bday_rsvps;

-- One row per RSVP, including private notes; for you ONLY.
create or replace view bday_admin.guest_list as
select
  player_name as "Player",
  case attendance when 'yes' then 'Coming' when 'maybe' then 'Maybe' else 'Not coming' end as "RSVP",
  case visit_mode
    when 'day' then 'Day only'
    when 'overnight' then 'Overnight only'
    when 'both' then 'Both'
    else 'Undecided'
  end as "Plan",
  case when visit_mode in ('overnight','both') then 1 else 0 end as "ON",
  case when visit_mode in ('day','both') then 1 else 0 end as "OD",
  pcs as "PCs",
  consoles as "Consoles total",
  case when 'Nintendo Switch 1' = any(console_types) then 1 else 0 end as "Switch 1",
  case when 'Nintendo Switch 2' = any(console_types) then 1 else 0 end as "Switch 2",
  case when 'Xbox' = any(console_types) then 1 else 0 end as "Xbox",
  case when 'PlayStation 4' = any(console_types) then 1 else 0 end as "PS4",
  case when 'PlayStation 5' = any(console_types) then 1 else 0 end as "PS5",
  case when 'Other' = any(console_types) then 1 else 0 end as "Other console",
  other_console as "Other console name",
  (monitors + tvs) as "Screens",
  case sidequest_interest
    when 'yes' then 'Interested'
    when 'maybe' then 'Maybe'
    else 'No'
  end as "Sidequest",
  case when stay_anonymous then 'Stealthed' else 'Public' end as "Roster visibility",
  notes as "Private notes",
  updated_at as "Last updated"
from public.bday_rsvps;

-- Explicit denial of client/API access (even if custom schemas are later exposed).
revoke all on bday_admin.summary from public, anon, authenticated, service_role;
revoke all on bday_admin.guest_list from public, anon, authenticated, service_role;

commit;

-- After running the setup above, open Supabase -> Table Editor and
-- choose schema "bday_admin" to browse "summary" and "guest_list".
-- Alternatively run either of the following individually in SQL Editor:
--
-- select * from bday_admin.summary;
-- select * from bday_admin.guest_list order by "Last updated" desc;
--
-- Views update automatically whenever an RSVP changes. These are read-only
-- for management; to edit a response manually, use public.bday_rsvps
-- in the authenticated Supabase dashboard only.

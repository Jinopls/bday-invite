-- PRIVATE-CONSENT AFK ROSTER UPGRADE (V5)
-- Run ONCE in Supabase Dashboard -> SQL Editor (or rerun safely).
-- This makes a separate AFK section for RSVPs marked "Sadly can't make it."
-- Only names of guests who submitted under the NEW clear public-name wording,
-- left "Stay Anonymous" unchecked, and declined are included.
-- Existing declined RSVPs are hidden by default; they can resubmit to opt in.
-- No existing attendance, notes, equipment or other RSVP data is deleted.

begin;

alter table public.bday_rsvps
  add column if not exists console_types text[] not null default '{}'::text[],
  add column if not exists other_console text not null default '',
  add column if not exists sidequest_interest text not null default 'no',
  add column if not exists afk_opt_in boolean not null default false;

alter table public.bday_rsvps
  drop constraint if exists bday_rsvps_visit_mode_check;
alter table public.bday_rsvps
  add constraint bday_rsvps_visit_mode_check
  check (visit_mode in ('day','overnight','both','unsure'));

-- The V5 submit function validates AFK opt-in. Keep older write
-- functions compatible if an RSVP later changes its attendance.

alter table public.bday_rsvps enable row level security;
revoke all on table public.bday_rsvps from public, anon, authenticated;

create or replace function public.bday_submit_v5(
  p_ticket uuid,
  p_name text,
  p_attendance text,
  p_mode text,
  p_is_anonymous boolean,
  p_pcs integer,
  p_consoles integer,
  p_monitors integer,
  p_tvs integer,
  p_games text[],
  p_notes text,
  p_console_types text[],
  p_other_console text,
  p_sidequest_interest text,
  p_afk_opt_in boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_ticket is null
    or p_name is null or char_length(btrim(p_name)) not between 1 and 90
    or p_attendance is null or p_attendance not in ('yes','maybe','no')
    or p_mode is null or p_mode not in ('overnight','day','both','unsure')
    or p_is_anonymous is null
    or p_pcs is null or p_pcs not between 0 and 8
    or p_consoles is null or p_consoles not between 0 and 8
    or p_monitors is null or p_monitors not between 0 and 8
    or p_tvs is null or p_tvs not between 0 and 8
    or p_games is null or cardinality(p_games) > 5
    or p_notes is null or char_length(p_notes) > 500
    or p_console_types is null or cardinality(p_console_types) > 6
    or p_other_console is null or char_length(p_other_console) > 70
    or p_sidequest_interest is null or p_sidequest_interest not in ('yes','maybe','no')
    or p_afk_opt_in is null
    or (p_afk_opt_in and (p_attendance <> 'no' or p_is_anonymous))
    or (p_consoles = 0 and cardinality(p_console_types) > 0)
    or (p_consoles > 0 and cardinality(p_console_types) = 0)
    or cardinality(p_console_types) > p_consoles
    or (('Other' = any(p_console_types)) <> (char_length(btrim(p_other_console)) > 0))
    or exists (
      select 1 from unnest(p_games) as g(value)
      where g.value not in ('Co-op','Party games','Competitive','Retro classics','Anything!')
         or g.value is null
    )
    or exists (
      select 1 from unnest(p_console_types) as c(value)
      where c.value not in ('Nintendo Switch 1','Nintendo Switch 2','Xbox','PlayStation 4','PlayStation 5','Other')
         or c.value is null
    )
    or cardinality(p_console_types) <> (
      select count(distinct c.value) from unnest(p_console_types) as c(value)
    )
  then
    raise exception 'Invalid RSVP details';
  end if;

  insert into public.bday_rsvps
    (ticket, player_name, attendance, visit_mode, stay_anonymous,
     pcs, consoles, monitors, tvs, games, notes, console_types, other_console, sidequest_interest, afk_opt_in)
  values
    (p_ticket, btrim(p_name), p_attendance, p_mode, p_is_anonymous,
     p_pcs, p_consoles, p_monitors, p_tvs, p_games, p_notes,
     p_console_types, btrim(p_other_console), p_sidequest_interest, p_afk_opt_in)
  on conflict (ticket) do update set
    player_name = excluded.player_name,
    attendance = excluded.attendance,
    visit_mode = excluded.visit_mode,
    stay_anonymous = excluded.stay_anonymous,
    pcs = excluded.pcs,
    consoles = excluded.consoles,
    monitors = excluded.monitors,
    tvs = excluded.tvs,
    games = excluded.games,
    notes = excluded.notes,
    console_types = excluded.console_types,
    other_console = excluded.other_console,
    sidequest_interest = excluded.sidequest_interest,
    afk_opt_in = excluded.afk_opt_in,
    updated_at = now();
end;
$$;

-- Public only receives group totals and the existing opt-in player roster.
-- No names, tickets, notes or other private RSVP details in Sidequest stats.

create or replace function public.bday_lobby_v5()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.bday_lobby() || jsonb_build_object(
    'day', count(*) filter (where r.attendance = 'yes' and r.visit_mode = 'day'),
    'overnight', count(*) filter (where r.attendance = 'yes' and r.visit_mode = 'overnight'),
    'both', count(*) filter (where r.attendance = 'yes' and r.visit_mode = 'both'),
    'unsure', count(*) filter (where r.attendance = 'yes' and r.visit_mode = 'unsure'),
    'sidequest_yes', count(*) filter (where r.attendance = 'yes' and r.sidequest_interest = 'yes'),
    'sidequest_maybe', count(*) filter (where r.attendance = 'yes' and r.sidequest_interest = 'maybe'),
    'afk_players', (
      select coalesce(jsonb_agg(
        jsonb_build_object('name', a.player_name) order by a.created_at
      ), '[]'::jsonb)
      from (
        select player_name, created_at
        from public.bday_rsvps
        where attendance = 'no'
          and stay_anonymous = false
          and afk_opt_in = true
        order by created_at
        limit 100
      ) a
    ),
    'console_breakdown', (
      select coalesce(jsonb_agg(
        jsonb_build_object('name', c.console_type, 'players', c.guests)
        order by c.guests desc, c.console_type
      ), '[]'::jsonb)
      from (
        select model.value as console_type, count(*) as guests
        from public.bday_rsvps guests
        cross join lateral unnest(guests.console_types) as model(value)
        where guests.attendance = 'yes'
        group by model.value
      ) c
    )
  )
  from public.bday_rsvps r;
$$;

revoke all on function public.bday_submit_v5(uuid,text,text,text,boolean,integer,integer,integer,integer,text[],text,text[],text,text,boolean)
  from public, anon, authenticated;
grant execute on function public.bday_submit_v5(uuid,text,text,text,boolean,integer,integer,integer,integer,text[],text,text[],text,text,boolean)
  to anon;

revoke all on function public.bday_lobby_v5()
  from public, anon, authenticated;
grant execute on function public.bday_lobby_v5() to anon;

commit;

-- Debug privately in the dashboard:
-- select player_name, attendance, stay_anonymous, afk_opt_in
-- from public.bday_rsvps order by created_at;

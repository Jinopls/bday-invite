-- BDAY & GAMES: run this entire file in your Supabase SQL Editor.
-- Public website receives only the aggregated lobby summary and opted-in gamer tags.
-- Private names/notes remain in this table and are visible to you in Supabase.
-- Keep your secret/service_role key out of GitHub and out of the website.

create table if not exists public.bday_rsvps (
  ticket uuid primary key,
  player_name text not null check (char_length(btrim(player_name)) between 1 and 90),
  attendance text not null check (attendance in ('yes','maybe','no')),
  visit_mode text not null check (visit_mode in ('overnight','day','unsure')),
  stay_anonymous boolean not null default true,
  pcs integer not null default 0 check (pcs between 0 and 8),
  consoles integer not null default 0 check (consoles between 0 and 8),
  monitors integer not null default 0 check (monitors between 0 and 8),
  tvs integer not null default 0 check (tvs between 0 and 8),
  games text[] not null default '{}'::text[],
  notes text not null default '' check (char_length(notes) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bday_rsvps enable row level security;
-- Neither guests nor signed-in users may read, insert, or update the table directly.
-- All guest operations are limited to the explicitly granted functions below.
revoke all on table public.bday_rsvps from public, anon, authenticated;

-- Anonymous visitors can submit a response and replace it ONLY when they
-- already know the private random ticket token saved in their own browser.
create or replace function public.bday_submit(
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
  p_notes text
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
    or p_mode is null or p_mode not in ('overnight','day','unsure')
    or p_is_anonymous is null
    or p_pcs is null or p_pcs not between 0 and 8
    or p_consoles is null or p_consoles not between 0 and 8
    or p_monitors is null or p_monitors not between 0 and 8
    or p_tvs is null or p_tvs not between 0 and 8
    or p_games is null or cardinality(p_games) > 5
    or p_notes is null or char_length(p_notes) > 500
    or exists (
      select 1 from unnest(p_games) as g(value)
      where g.value not in ('Co-op','Party games','Competitive','Retro classics','Anything!')
    )
  then
    raise exception 'Invalid RSVP details';
  end if;

  insert into public.bday_rsvps
    (ticket, player_name, attendance, visit_mode, stay_anonymous, pcs, consoles, monitors, tvs, games, notes)
  values
    (p_ticket, btrim(p_name), p_attendance, p_mode, p_is_anonymous,
     p_pcs, p_consoles, p_monitors, p_tvs, p_games, p_notes)
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
    updated_at = now();
end;
$$;

-- Only approved public information is returned. No names from anonymous
-- guests, private notes, tickets, or other personal details are exposed.
create or replace function public.bday_lobby()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'confirmed', count(*) filter (where r.attendance = 'yes'),
    'maybe', count(*) filter (where r.attendance = 'maybe'),
    'stealthed', count(*) filter (where r.attendance = 'yes' and r.stay_anonymous),
    'overnight', count(*) filter (where r.attendance = 'yes' and r.visit_mode = 'overnight'),
    'day', count(*) filter (where r.attendance = 'yes' and r.visit_mode = 'day'),
    'unsure', count(*) filter (where r.attendance = 'yes' and r.visit_mode = 'unsure'),
    'pcs', coalesce(sum(r.pcs) filter (where r.attendance = 'yes'), 0),
    'consoles', coalesce(sum(r.consoles) filter (where r.attendance = 'yes'), 0),
    'monitors', coalesce(sum(r.monitors) filter (where r.attendance = 'yes'), 0),
    'tvs', coalesce(sum(r.tvs) filter (where r.attendance = 'yes'), 0),
    'players', (
      select coalesce(jsonb_agg(
        jsonb_build_object('name', p.player_name, 'mode', p.visit_mode)
        order by p.created_at
      ), '[]'::jsonb)
      from (
        select player_name, visit_mode, created_at
        from public.bday_rsvps
        where attendance = 'yes' and stay_anonymous = false
        order by created_at
        limit 100
      ) p
    ),
    'games', (
      select coalesce(jsonb_agg(
        jsonb_build_object('name', v.game, 'votes', v.votes)
        order by v.votes desc, v.game
      ), '[]'::jsonb)
      from (
        select g.game, count(*) as votes
        from public.bday_rsvps a
        cross join lateral unnest(a.games) as g(game)
        where a.attendance = 'yes'
        group by g.game
      ) v
    )
  )
  from public.bday_rsvps r;
$$;

revoke all on function public.bday_submit(uuid,text,text,text,boolean,integer,integer,integer,integer,text[],text) from public, anon, authenticated;
grant execute on function public.bday_submit(uuid,text,text,text,boolean,integer,integer,integer,integer,text[],text) to anon;

revoke all on function public.bday_lobby() from public, anon, authenticated;
grant execute on function public.bday_lobby() to anon;

-- Admin view (run in the private SQL editor when you want the full list):
-- select * from public.bday_rsvps order by created_at;

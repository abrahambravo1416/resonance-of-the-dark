-- Telemetría de partidas para el panel de Resonance of the Dark.
-- Solo la Edge Function (service role) puede escribir o leer estas tablas.

create table if not exists public.game_sessions (
    session_id text primary key check (char_length(session_id) between 1 and 200),
    player_name text not null default 'Visitante',
    game_version text not null default '',
    started_at double precision not null,
    last_seen double precision not null,
    ended_at double precision,
    outcome text,
    created_at timestamptz not null default now()
);

create table if not exists public.game_events (
    event_id text primary key check (char_length(event_id) between 1 and 200),
    session_id text not null references public.game_sessions(session_id) on delete cascade,
    seq bigint not null check (seq >= 0),
    kind text not null check (char_length(kind) between 1 and 100),
    ts double precision not null,
    elapsed double precision not null default 0,
    level integer not null default 0,
    x double precision,
    y double precision,
    z double precision,
    data jsonb not null default '{}'::jsonb
);

create index if not exists game_events_session_order on public.game_events(session_id, seq, ts);
create index if not exists game_events_session_level on public.game_events(session_id, level);
create index if not exists game_events_kind on public.game_events(kind);

alter table public.game_sessions enable row level security;
alter table public.game_events enable row level security;
revoke all on public.game_sessions, public.game_events from anon, authenticated;
grant select, insert, update, delete on public.game_sessions, public.game_events to service_role;

create or replace function public.ingest_gameplay_batch(p_events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    inserted_count integer := 0;
begin
    if jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) < 1 or jsonb_array_length(p_events) > 100 then
        raise exception 'Expected an array with 1 to 100 events';
    end if;

    with incoming as (
        select event.session_id, event.ts, event.seq, event.kind, event.data
        from jsonb_to_recordset(p_events) as event(
            session_id text, ts double precision, seq bigint, kind text, data jsonb
        )
    ), grouped as (
        select
            session_id,
            min(ts) as started_at,
            max(ts) as last_seen,
            coalesce(max(data ->> 'player_name') filter (where kind = 'session_started'), 'Visitante') as player_name,
            coalesce(max(data ->> 'game_version') filter (where kind = 'session_started'), '') as game_version,
            max(ts) filter (where kind = 'session_ended') as ended_at,
            (array_agg(data ->> 'outcome' order by seq desc) filter (where kind = 'session_ended'))[1] as outcome
        from incoming
        group by session_id
    )
    insert into public.game_sessions as current_session(session_id, player_name, game_version, started_at, last_seen, ended_at, outcome)
    select session_id, player_name, game_version, started_at, last_seen, ended_at, outcome
    from grouped
    on conflict (session_id) do update set
        player_name = case
            when current_session.player_name in ('', 'Visitante') and excluded.player_name <> '' then excluded.player_name
            else current_session.player_name
        end,
        game_version = case
            when current_session.game_version = '' and excluded.game_version <> '' then excluded.game_version
            else current_session.game_version
        end,
        started_at = least(current_session.started_at, excluded.started_at),
        last_seen = greatest(current_session.last_seen, excluded.last_seen),
        ended_at = coalesce(current_session.ended_at, excluded.ended_at),
        outcome = coalesce(current_session.outcome, excluded.outcome);

    with incoming as (
        select
            event.event_id, event.session_id, event.seq, event.kind, event.ts,
            greatest(0.0, event.elapsed) as elapsed,
            greatest(0, event.level) as level,
            case when jsonb_typeof(event.position) = 'object' then nullif(event.position ->> 'x', '')::double precision end as x,
            case when jsonb_typeof(event.position) = 'object' then nullif(event.position ->> 'y', '')::double precision end as y,
            case when jsonb_typeof(event.position) = 'object' then nullif(event.position ->> 'z', '')::double precision end as z,
            coalesce(event.data, '{}'::jsonb) as data
        from jsonb_to_recordset(p_events) as event(
            event_id text, session_id text, seq bigint, kind text, ts double precision,
            elapsed double precision, level integer, position jsonb, data jsonb
        )
    )
    insert into public.game_events(event_id, session_id, seq, kind, ts, elapsed, level, x, y, z, data)
    select event_id, session_id, seq, kind, ts, elapsed, level, x, y, z, data
    from incoming
    on conflict (event_id) do nothing;

    get diagnostics inserted_count = row_count;
    return jsonb_build_object('accepted', inserted_count);
end;
$$;

revoke all on function public.ingest_gameplay_batch(jsonb) from public, anon, authenticated;
grant execute on function public.ingest_gameplay_batch(jsonb) to service_role;

create or replace view public.game_session_summary as
with event_counts as (
    select
        session_id,
        count(*)::bigint as event_count,
        count(*) filter (where kind not in (
            'position', 'position_sample', 'player_position', 'movement_sample', 'enemy_position_sample'
        ))::bigint as action_count,
        count(distinct level) filter (where level > 0)::integer as level_count,
        coalesce(max(elapsed), 0.0)::double precision as duration
    from public.game_events
    group by session_id
), sample_steps as (
    select
        session_id,
        level,
        coalesce(data ->> 'attempt', '0') as attempt,
        sqrt(power(x - lag(x) over (partition by session_id, level, coalesce(data ->> 'attempt', '0') order by seq, ts), 2)
            + power(z - lag(z) over (partition by session_id, level, coalesce(data ->> 'attempt', '0') order by seq, ts), 2)) as step_distance
    from public.game_events
    where kind in ('position', 'position_sample', 'player_position', 'movement_sample') and x is not null and z is not null
), distances as (
    select session_id, coalesce(sum(step_distance), 0.0)::double precision as distance
    from sample_steps
    group by session_id
)
select
    session.session_id,
    session.player_name,
    session.game_version,
    session.started_at,
    session.last_seen,
    session.ended_at,
    session.outcome,
    coalesce(counts.event_count, 0)::bigint as event_count,
    coalesce(counts.action_count, 0)::bigint as action_count,
    coalesce(counts.level_count, 0)::integer as level_count,
    coalesce(counts.duration, 0.0)::double precision as duration,
    round(coalesce(distance.distance, 0.0)::numeric, 2)::double precision as distance
from public.game_sessions as session
left join event_counts as counts using (session_id)
left join distances as distance using (session_id);

revoke all on public.game_session_summary from public, anon, authenticated;
grant select on public.game_session_summary to service_role;

-- Identificador seudonimo estable por instalacion para agrupar distintas partidas.
-- No es una cuenta ni verifica la identidad real de quien juega.

alter table public.game_sessions
    add column if not exists player_id text;

create index if not exists game_sessions_player_id_started_at
    on public.game_sessions (player_id, started_at desc)
    where player_id is not null;

create or replace function public.capture_game_session_player_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    incoming_player_id text;
begin
    if new.kind = 'session_started' then
        incoming_player_id := left(nullif(btrim(new.data ->> 'player_id'), ''), 100);
        if incoming_player_id is not null then
            update public.game_sessions
            set player_id = incoming_player_id
            where session_id = new.session_id and player_id is null;
        end if;
    end if;
    return new;
end;
$$;

revoke all on function public.capture_game_session_player_id() from public, anon, authenticated;

drop trigger if exists capture_game_session_player_id on public.game_events;
create trigger capture_game_session_player_id
after insert on public.game_events
for each row execute function public.capture_game_session_player_id();

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
    round(coalesce(distance.distance, 0.0)::numeric, 2)::double precision as distance,
    session.player_id
from public.game_sessions as session
left join event_counts as counts using (session_id)
left join distances as distance using (session_id);

revoke all on public.game_session_summary from public, anon, authenticated;
grant select on public.game_session_summary to service_role;

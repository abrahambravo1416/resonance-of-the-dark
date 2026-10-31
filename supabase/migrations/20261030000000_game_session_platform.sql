-- Records whether a session was played on a computer or a mobile device.
-- Existing sessions remain "unknown" because their original device cannot be inferred.
alter table public.game_sessions
    add column if not exists platform text not null default 'unknown';

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'public.game_sessions'::regclass
          and conname = 'game_sessions_platform_check'
    ) then
        alter table public.game_sessions
            add constraint game_sessions_platform_check
            check (platform in ('pc', 'mobile', 'unknown'));
    end if;
end;
$$;

-- The session_started event is already inserted by the ingestion RPC.
-- Extend the existing trigger function without changing its player ID behavior.
create or replace function public.capture_game_session_player_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    incoming_player_id text;
    incoming_platform text;
begin
    if new.kind = 'session_started' then
        incoming_player_id := left(nullif(btrim(new.data ->> 'player_id'), ''), 100);
        incoming_platform := lower(nullif(btrim(new.data ->> 'platform'), ''));

        update public.game_sessions
        set player_id = coalesce(player_id, incoming_player_id),
            platform = case
                when platform = 'unknown' and incoming_platform in ('pc', 'mobile') then incoming_platform
                else platform
            end
        where session_id = new.session_id;
    end if;
    return new;
end;
$$;

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
    session.player_id,
    session.platform
from public.game_sessions as session
left join event_counts as counts using (session_id)
left join distances as distance using (session_id);

revoke all on public.game_session_summary from public, anon, authenticated;
grant select on public.game_session_summary to service_role;

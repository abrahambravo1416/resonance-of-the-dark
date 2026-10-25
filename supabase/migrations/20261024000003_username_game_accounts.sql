-- Username/password accounts are handled only by the account-api Edge Function.
-- The client has no Data API grants on these tables.
create table if not exists public.game_accounts (
    id uuid primary key default gen_random_uuid(),
    username text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
    password_hash text not null,
    created_at timestamptz not null default now()
);

create table if not exists public.game_account_sessions (
    token_hash text primary key,
    account_id uuid not null references public.game_accounts(id) on delete cascade,
    expires_at timestamptz not null,
    created_at timestamptz not null default now()
);

create index if not exists game_account_sessions_account_created
    on public.game_account_sessions (account_id, created_at desc);
create index if not exists game_account_sessions_expiry
    on public.game_account_sessions (expires_at);

create table if not exists public.game_account_saves (
    account_id uuid not null references public.game_accounts(id) on delete cascade,
    slot smallint not null check (slot between 1 and 3),
    save_name text not null default 'Partida' check (char_length(save_name) between 1 and 48),
    level smallint not null default 1 check (level between 1 and 4),
    score integer not null default 0,
    save_data jsonb not null default '{}'::jsonb check (pg_column_size(save_data) <= 65536),
    updated_at timestamptz not null default now(),
    primary key (account_id, slot)
);

create table if not exists public.game_auth_rate_limits (
    rate_key text primary key,
    window_started_at timestamptz not null default now(),
    attempts integer not null default 0
);

alter table public.game_accounts enable row level security;
alter table public.game_account_sessions enable row level security;
alter table public.game_account_saves enable row level security;
alter table public.game_auth_rate_limits enable row level security;

revoke all on public.game_accounts, public.game_account_sessions,
    public.game_account_saves, public.game_auth_rate_limits
    from public, anon, authenticated;
grant all on public.game_accounts, public.game_account_sessions,
    public.game_account_saves, public.game_auth_rate_limits to service_role;

create or replace function public.consume_game_auth_attempt(p_rate_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    attempt_count integer;
begin
    delete from public.game_auth_rate_limits
    where window_started_at < now() - interval '1 day';

    insert into public.game_auth_rate_limits (rate_key, window_started_at, attempts)
    values (p_rate_key, now(), 1)
    on conflict (rate_key) do update
    set attempts = case
            when public.game_auth_rate_limits.window_started_at < now() - interval '15 minutes' then 1
            else public.game_auth_rate_limits.attempts + 1
        end,
        window_started_at = case
            when public.game_auth_rate_limits.window_started_at < now() - interval '15 minutes' then now()
            else public.game_auth_rate_limits.window_started_at
        end
    returning attempts into attempt_count;

    return attempt_count <= 10;
end;
$$;

revoke all on function public.consume_game_auth_attempt(text) from public, anon, authenticated;
grant execute on function public.consume_game_auth_attempt(text) to service_role;

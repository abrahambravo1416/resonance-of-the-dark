-- Only explicitly approved game accounts can read the shared gameplay archive.
create table if not exists public.game_dashboard_viewers (
    account_id uuid primary key references public.game_accounts(id) on delete cascade,
    granted_at timestamptz not null default now()
);

alter table public.game_dashboard_viewers enable row level security;
revoke all on public.game_dashboard_viewers from public, anon, authenticated;
grant all on public.game_dashboard_viewers to service_role;

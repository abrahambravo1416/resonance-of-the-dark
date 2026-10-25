-- Tres espacios de progreso por cuenta autenticada. Los invitados no escriben aquí.
create table if not exists public.game_saves (
    user_id uuid not null references auth.users(id) on delete cascade,
    slot smallint not null check (slot between 1 and 3),
    save_name text not null default 'Partida' check (char_length(save_name) between 1 and 48),
    level smallint not null default 1 check (level between 1 and 4),
    score integer not null default 0,
    save_data jsonb not null default '{}'::jsonb check (pg_column_size(save_data) <= 65536),
    updated_at timestamptz not null default now(),
    primary key (user_id, slot)
);

create index if not exists game_saves_user_updated
    on public.game_saves (user_id, updated_at desc);

alter table public.game_saves enable row level security;
revoke all on public.game_saves from anon, authenticated;
grant select, insert, update, delete on public.game_saves to authenticated;

drop policy if exists "Players can read their own saves" on public.game_saves;
create policy "Players can read their own saves"
    on public.game_saves for select to authenticated
    using (
        auth.uid() = user_id
        and coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true'
    );

drop policy if exists "Players can create their own saves" on public.game_saves;
create policy "Players can create their own saves"
    on public.game_saves for insert to authenticated
    with check (
        auth.uid() = user_id
        and coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true'
    );

drop policy if exists "Players can update their own saves" on public.game_saves;
create policy "Players can update their own saves"
    on public.game_saves for update to authenticated
    using (
        auth.uid() = user_id
        and coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true'
    )
    with check (
        auth.uid() = user_id
        and coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true'
    );

drop policy if exists "Players can delete their own saves" on public.game_saves;
create policy "Players can delete their own saves"
    on public.game_saves for delete to authenticated
    using (
        auth.uid() = user_id
        and coalesce(auth.jwt() ->> 'is_anonymous', 'false') <> 'true'
    );

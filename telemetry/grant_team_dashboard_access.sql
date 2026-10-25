-- Cambia los nombres por los IDs de juego de las personas autorizadas.
-- Cada persona debe haber creado antes su cuenta desde el menú del juego.
insert into public.game_dashboard_viewers (account_id)
select id
from public.game_accounts
where username in ('tu_id', 'id_del_companero')
on conflict (account_id) do nothing;

-- Para retirar el acceso a alguien:
-- delete from public.game_dashboard_viewers
-- where account_id = (select id from public.game_accounts where username = 'id_del_companero');

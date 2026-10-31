# Conectar el archivo de partidas a Supabase

El proyecto queda preparado para guardar las sesiones de todas las instalaciones en una base central de Supabase. El juego conserva su diario JSONL local y lo sube en lotes cuando hay conexión. Los eventos tienen `event_id` único, por lo que un reintento no duplica datos.

## 1. Crear el proyecto gratuito

1. Crea un proyecto en [Supabase](https://supabase.com/dashboard).
2. En **Settings → API Keys**, copia la **Project URL** y la clave **Publishable** (`sb_publishable_...`). La clave publishable se puede distribuir con un juego.
3. No copies la clave **Secret** (`sb_secret_...`) al proyecto Godot, a la app distribuida, al repositorio ni al chat. Solo se usa desde la función de Supabase o desde el panel privado de administración.

El plan Free tiene límites de almacenamiento, transferencia y ejecuciones; consulta los límites vigentes en [precios y cuotas](https://supabase.com/docs/guides/platform/billing-on-supabase). Los proyectos Free inactivos pueden pausarse; se pueden reanudar desde el Dashboard y la pausa no equivale a borrar el proyecto. Revisa la [política de pausa](https://supabase.com/docs/guides/platform/free-project-pausing) antes de publicar.

## 2. Desplegar base y función receptora

Instala el [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) y, desde la raíz del repositorio, ejecuta en PowerShell:

```powershell
supabase login
supabase link --project-ref TU_PROJECT_REF
supabase db push
supabase functions deploy ingest-gameplay
```

`TU_PROJECT_REF` es el identificador del proyecto que aparece en su URL del Dashboard. `db push` instala las migraciones locales pendientes: tablas de telemetría, identidad seudónima y espacios de guardado de cuentas. El despliegue publica `supabase/functions/ingest-gameplay/index.ts`.

La función acepta únicamente una clave publishable válida, valida el tamaño y los campos de cada lote, y escribe mediante el rol privilegiado en el servidor. El cliente no recibe permisos directos sobre las tablas de telemetría. La tabla de partidas guardadas sí usa la API REST con la sesión autenticada del jugador y políticas RLS que limitan cada fila a su propietario.

## 3. Configurar el juego

En Godot, abre `scenes/systems/GameplayLog.tscn` y selecciona el nodo raíz `GameplayLog`. En el Inspector, configura:

- `remote_ingest_url`: `https://TU_PROJECT_REF.supabase.co/functions/v1/ingest-gameplay`
- `remote_publishable_key`: la clave `sb_publishable_...`

Estos dos valores identifican un cliente público; la clave publishable no es un secreto. Al iniciar el juego, los JSONL pendientes de la carpeta local también se intentan sincronizar, así que el registro local acumulado puede subirse cuando configures el endpoint. Para que funcione en las copias que descarguen otras personas, exporta y distribuye una nueva versión del juego con esta configuración.

La sincronización se intenta al comenzar una sesión, al entrar a un nivel, al cerrar la partida y por lotes cada 15 segundos mientras se juega. Si falla la conexión, el avance de carga no se confirma y el mismo lote se reintenta; el diario queda guardado localmente y se volverá a intentar cuando el juego se ejecute otra vez. Las partidas permanecen en `user://telemetry/spool` hasta que el usuario borre los datos locales.

Cada sesión nueva incluye `platform` (`pc` o `mobile`). El panel muestra el dispositivo en una tarjeta y en cada partida, y permite filtrar por PC, Móvil o registros antiguos sin plataforma. Las sesiones existentes anteriores a esta versión aparecen como **Desconocido** porque la plataforma no se guardó en su momento. Para que las sesiones móviles puedan conectarse a Supabase, el preset Android del proyecto ya tiene activado el permiso **Internet**; vuelve a exportar e instalar el APK actualizado.

La nueva migración `20261030000000_game_session_platform.sql` agrega la columna `game_sessions.platform` y la expone en `game_session_summary`. Aplícala desde la raíz del repositorio con `supabase db push`. Después sube los cambios del panel web a GitHub para publicar el filtro y la tarjeta de plataforma.

## 4. Iniciar automáticamente el panel de partidas central

El panel existente escucha solo en `127.0.0.1`. En Windows puedes guardar la clave **Secret** una sola vez, protegida con DPAPI para tu usuario de Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\telemetry\setup_dashboard_credentials.ps1"
```

El script pide la clave sin mostrarla y la cifra para la cuenta actual de Windows en `%LOCALAPPDATA%\ResonanceOfTheDark`. No la guarda en el repositorio. A partir de entonces, al iniciar una partida, el juego puede iniciar el panel automáticamente en `http://127.0.0.1:8765`; el panel consulta Supabase y sigue importando el respaldo local.

El arranque automático necesita Python 3 instalado. Si no se guardó la clave, el panel funciona en su modo SQLite local. Para iniciarlo manualmente puedes usar las variables `SUPABASE_URL` y `SUPABASE_SECRET_KEY` en una terminal privada. También se admite `SUPABASE_SERVICE_ROLE_KEY` por compatibilidad, aunque en proyectos nuevos debes usar `SUPABASE_SECRET_KEY`.

Si un servidor anterior mantiene ocupado el puerto, el lanzador intenta reiniciar únicamente un proceso `telemetry/server.py` que ya esté escuchando en ese puerto. Los mensajes de arranque se escriben en `%LOCALAPPDATA%\ResonanceOfTheDark\dashboard.log`.

## Identidad del jugador y límites

- El juego crea un `player_id` aleatorio al iniciar por primera vez y lo conserva en `user://player_profile.cfg`. El nombre opcional del menú también se guarda localmente y se envía como nombre visible.
- Las partidas nuevas de la misma instalación se pueden agrupar por `player_id`. El panel muestra ese identificador y cuántas partidas están asociadas a él.
- Esto no crea una cuenta ni verifica una identidad real: al cambiar de computadora, borrar los datos del juego o reinstalar limpiando `user://`, se creará otro identificador. Las partidas antiguas no se pueden asociar retroactivamente.
- Para que Supabase central y el panel muestren los identificadores nuevos, instala la migración adicional desde la raíz del proyecto con `supabase db push`. La migración agrega una columna y una vista; conserva las sesiones y eventos existentes.
- Cada sesión conserva también versión, niveles, acciones, muestras de posición y estados de enemigos que el juego ya registra.
- Esto solo recopila las partidas jugadas en una build configurada con el endpoint. Las copias antiguas no empiezan a enviar datos retroactivamente. Los diarios existentes en una computadora sí se pueden subir cuando esa build los encuentre en su spool local.
- La base alojada es el archivo central. El JSONL y SQLite siguen siendo copias locales; borrar una de ellas no elimina la otra.
- Antes de distribuir el juego, informa que se envían eventos y posiciones de juego a Supabase, y ofrece un modo de desactivar la telemetría si se requiere consentimiento explícito.

## IDs de jugador y tres espacios de guardado

El menú ofrece dos caminos: **Jugar como invitado** empieza una campaña nueva sin cuenta; **Iniciar sesión · partidas** permite crear o usar un ID único y una contraseña, y muestra tres espacios por ID. No pide ni envía correos.

El ID admite de 3 a 20 letras minúsculas, números o guion bajo; el servidor normaliza a minúsculas y rechaza duplicados. La contraseña debe tener al menos 8 caracteres. El servidor guarda un hash bcrypt, nunca el texto de la contraseña. Cada sesión usa un token aleatorio guardado en el dispositivo y caduca a los 90 días. Si se olvida la contraseña, no hay recuperación automática porque no se recopila correo; la cuenta y sus espacios no se podrán recuperar sin asistencia administrativa.

Las tablas de cuentas y partidas no son accesibles desde el cliente. La Edge Function `account-api` valida el ID/contraseña, aplica límites a intentos de acceso y procesa los tres espacios en el servidor. No coloques `sb_secret` ni la antigua `service_role` en Godot. La nueva tabla de progreso es `public.game_account_saves`; las tablas de la autenticación anterior por correo se conservan sin usarse para no borrar datos.

Las partidas guardan un punto de control al continuar entre niveles, al perder y al completar el Nivel 4. Si se cierra el juego durante un nivel, continuar vuelve al inicio de ese nivel con la puntuación y penalizaciones del último punto de control; no guarda cada movimiento u objetivo en tiempo real. Si falla internet al guardar un punto de control, queda pendiente en `user://` y se vuelve a intentar al reconectar.

Para desplegar el sistema desde la raíz del repositorio:

```powershell
supabase db push
supabase functions deploy account-api
```

El menú aparece en la siguiente ejecución del proyecto y en cualquier build que exportes después del cambio. Los invitados no leen ni escriben espacios de cuenta.

## Referencias del código

- Esquema y permisos: `supabase/migrations/20261024000000_gameplay_telemetry.sql`
- Identidad seudónima por instalación: `supabase/migrations/20261024000001_persistent_player_identity.sql`
- Receptor de lotes: `supabase/functions/ingest-gameplay/index.ts`
- Sincronización local: `scripts/GameplayLog.gd`
- Panel con consulta remota: `telemetry/server.py`
- ID/contraseña, sesión y sincronización de puntos de control: `scripts/CloudAccount.gd`
- Menú de cuenta y espacios: `scripts/SaveSlotsMenu.gd`
- Tablas privadas de ID, sesión y espacios: `supabase/migrations/20261024000003_username_game_accounts.sql`
- API segura de cuentas y partidas: `supabase/functions/account-api/index.ts`

## Compartir el archivo completo con el equipo

El panel `http://localhost:8765` sigue siendo local. Para que el equipo consulte el mismo archivo desde internet, el repositorio ahora incluye una versión web estática y una Edge Function privada. La web no contiene la clave secret; inicia sesión con la cuenta del juego y la función comprueba que el ID esté autorizado antes de entregar sesiones o eventos.

### Publicar la web

1. Desde la raíz del proyecto, aplica la nueva migración y despliega las funciones:

   ```powershell
   supabase db push
   supabase functions deploy account-api
   supabase functions deploy team-dashboard
   ```

2. Sube los cambios a la rama `main` de GitHub.
3. En GitHub, abre el repositorio y ve a **Settings → Pages**. En **Build and deployment → Source**, selecciona **GitHub Actions**.
4. En **Actions**, espera a que termine correctamente **Deploy gameplay archive**. GitHub mostrará la dirección del sitio en **Settings → Pages**. Comparte esa dirección con el equipo.

El archivo web y la clave `sb_publishable` son públicos; el archivo de partidas no lo es. La publishable key no concede permiso para leer telemetría. La función comprueba el token de la cuenta y la tabla `game_dashboard_viewers` para cada consulta. No publiques nunca `sb_secret` ni `service_role` en el sitio, en Godot ni en GitHub.

### Autorizar a cada integrante

Cada integrante debe crear una cuenta desde **Iniciar sesión** en el juego. Después, un administrador abre **Supabase → SQL Editor** y ejecuta el contenido de `telemetry/grant_team_dashboard_access.sql`, sustituyendo `tu_id` y `id_del_companero` por los IDs exactos. Esos IDs quedan autorizados a consultar **todas las partidas enviadas al proyecto**, no solo las suyas. Para retirar el acceso, ejecuta el `DELETE` comentado al final del archivo con el ID correspondiente.

Los invitados sin cuenta no pueden iniciar sesión en el archivo compartido. La autorización del panel no da acceso a la consola de Supabase ni a las partidas guardadas de otras cuentas.

El sitio de GitHub Pages es público como página; la pantalla de inicio de sesión solo protege el contenido entregado por la API. El repositorio también puede contener código público. GitHub Pages en planes Free requiere que el repositorio sea público; si el repositorio del equipo es privado y Pages no está disponible, se debe publicar `telemetry/web` en un hosting estático con soporte para el repo privado.

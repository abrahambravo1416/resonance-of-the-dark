# Archivo local de partidas

Para guardar partidas de todas las instalaciones en una base central Supabase, sigue [`SUPABASE_SETUP.md`](SUPABASE_SETUP.md). El modo local descrito abajo se mantiene como respaldo.

Para que integrantes del equipo consulten el mismo archivo desde internet, la guía de Supabase también incluye el despliegue de la web compartida. Cada lector debe iniciar sesión con su cuenta del juego y estar autorizado por un administrador; la web no expone la clave secreta ni permite leer el archivo a cualquier jugador.

El juego conserva un diario por sesión y este servicio lo importa a **SQLite**. La web muestra las partidas reales, sus acciones y el recorrido del jugador sobre el plano X/Z del nivel. El panel local no necesita MySQL, paquetes de Python, una cuenta ni conexión a internet; las cuentas son opcionales y se usan para guardar campañas en la nube.

## Abrir la página

Necesitas Python 3.9 o posterior. Desde la carpeta del proyecto:

```sh
python3 telemetry/server.py
```

En Windows puedes usar `python telemetry/server.py`. Abre **http://127.0.0.1:8765**. Deja esa terminal abierta; `Ctrl+C` detiene el servidor. El juego también intenta iniciar este servicio al comenzar una sesión. Si ya estaba abierto, usa la página existente; no necesitas un segundo servidor.

Si otro programa ocupa el puerto, ejecuta `python3 telemetry/server.py --port 8766` y abre `http://127.0.0.1:8766`. El servicio escucha únicamente en esta computadora.

## Qué puedes consultar

- Lista de sesiones, nombre del jugador, fecha, duración y estado.
- Tiempo registrado, distancia aproximada, cantidad de acciones y niveles visitados.
- Filtros por nivel, intento y tipo de actividad. Las muestras de posición se pueden mostrar aparte.
- Recorrido sobre la geometría del nivel; obstáculos y altares se obtienen de los nodos reales del juego. El plano muestra coordenadas X/Z, no una captura de pantalla del nivel.
- Reproducción de la ruta, control de tiempo, acercamiento, alejamiento y arrastre del plano. Pulsa la hora de una acción para ver ese momento.
- Registro cronológico con datos de cada evento y exportación CSV. También existe exportación JSON por API.

La ruta y la distancia usan las muestras de posición **del jugador**. Las muestras enemigas tampoco cuentan como acciones. Cada enemigo aparece con una etiqueta E1/E2, orientación y color según patrulla, investigación o persecución. El plano muestra la última posición conocida de cada uno hasta el instante seleccionado, sin anticipar posiciones ni extrapolar durante una pausa. Cada nivel e intento tiene pistas independientes.

El jugador oculto aparece en azul, con un círculo y la etiqueta **OCULTO**. Las transiciones actualizan su estado aunque esté inmóvil; la barra de reproducción señala los intervalos de ocultación y distingue su recorrido. La salida física del escondite conserva el estado oculto hasta que termina, conforme a las reglas del juego. Las partidas antiguas siguen siendo consultables, pero no tienen muestras enemigas continuas.

La distancia usa unidades del mundo de Godot como metros y es aproximada por el intervalo de muestreo; no incluye desplazamiento vertical.

“En curso” significa que llegó un evento en los últimos 45 segundos. Una partida sin cierre registrado pasa a “Sin actividad reciente”; esto puede ocurrir si se fuerza el cierre del juego. La página comprueba cambios cada cinco segundos.

## Archivos y persistencia

```text
telemetry/
  server.py              Servicio HTTP e importación
  schema.sql             Esquema de SQLite, incluido en Git
  web/                   HTML, CSS y JavaScript de la página
  test_server.py         Pruebas con datos temporales aislados
  data/
    resonance.sqlite3    Base de datos creada automáticamente
    spool/*.jsonl        Un diario duradero por sesión del juego
```

El código, la página y el esquema están en el repositorio. La base y los diarios reales se generan localmente dentro de esta carpeta y se excluyen de Git. No se incluyen partidas de ejemplo. SQLite usa WAL; cuando el servidor está activo también pueden existir archivos `-wal` y `-shm`. Detén el servidor antes de copiar la base sola o usa las exportaciones del panel.

El juego escribe y vacía el diario a disco después de cada evento. No necesita que la web esté abierta. El importador revisa los archivos cada segundo y antes de una consulta; importa cada `event_id` una sola vez. Si la última línea aún se está escribiendo, espera hasta recibir su salto de línea. Registros inválidos se cuentan y se omiten sin bloquear los demás. Los archivos JSONL deben tratarse como diarios de solo anexado.

Las tablas de telemetría (`game_sessions`, `game_events`) guardan **el historial para consulta**, no una partida guardada para reanudar el estado del juego. El progreso de las cuentas y sus tres espacios se conserva por separado en `public.game_account_saves`, mediante IDs y contraseñas validados en una Edge Function.

En una exportación del juego, Godot puede guardar el diario en `user://telemetry/spool`. Para consultar esa carpeta desde este proyecto:

```sh
python3 telemetry/server.py --spool-dir "/ruta/al/user/telemetry/spool"
```

En macOS, `user://` normalmente está dentro de `~/Library/Application Support/Godot/app_userdata/`; la carpeta exacta corresponde al nombre del proyecto. También puedes definir `RESONANCE_LOG_DIR` al ejecutar el juego para elegir el directorio de diarios. Para pruebas sin iniciar automáticamente la web, usa `RESONANCE_DISABLE_WEB=1`.

## Esquema y API

`sessions` conserva la identidad, jugador, versión, fechas y resultado de la sesión. `events` guarda eventos ordenados, nivel, posición opcional y datos específicos en JSON. `ingestion_sources` conserva la posición de lectura de cada diario para continuar después de reiniciar el servidor.

Cada línea JSONL tiene esta forma (descripción del contrato; no se inserta en la base):

```json
{"event_id":"sesion:1","session_id":"sesion","seq":1,"kind":"position_sample","ts":1750000000.5,"elapsed":2.5,"level":1,"position":{"x":4.2,"y":0.0,"z":8.0},"data":{"attempt":1}}
```

`position` es opcional. `session_started.data` puede incluir el `player_id` seudónimo de la instalación, el nombre visible del jugador y `game_version`; `session_ended.data` incluye `outcome`. `level_started.data` incluye `title`, `scene`, `map_bounds` y `map_geometry`. Todos los eventos pueden incluir `data.attempt` para distinguir reinicios del mismo nivel. El perfil se guarda en `user://player_profile.cfg`; borrar ese archivo genera una identidad nueva.

- `enemy_position_sample`: posición global, `enemy_id` (ruta relativa al nivel), `enemy` (nombre), `state` y `yaw`. Se guarda cada 0,5 segundos por defecto, independientemente del movimiento del jugador. `enemy_removed` termina la pista cuando el nodo desaparece.
- `position_sample`: además de posición, incluye `hidden`, `hiding`, `hidden_by_zone`, `cover` y `cover_type`.
- `hide_started`, `hide_ended`, `hide_exit_completed`, `hiding_zone_entered` y `hiding_zone_left`: cambios exactos de ocultación, con estado efectivo y posición. Las muestras de posición periódicas complementan estas transiciones.

| Petición GET | Respuesta |
| --- | --- |
| `/api/health` | Estado de SQLite, cantidades y líneas rechazadas |
| `/api/sessions` | `{ "sessions": [...] }`, más recientes primero |
| `/api/sessions/<session_id>` | `{ "session": {...}, "events": [...] }` |
| `/api/export/<session_id>?format=csv` | Archivo CSV con todos los eventos de esa sesión |
| `/api/export/<session_id>?format=json` | Archivo JSON con resumen y eventos |

Los filtros y la reproducción de la web no alteran los datos. Las consultas SQL usan parámetros y el servidor publica una lista explícita de archivos web; no expone el archivo SQLite ni permite ejecutar SQL desde la página. La exportación CSV neutraliza fórmulas en campos de texto para abrirla en una hoja de cálculo.

## Verificación

```sh
python3 -m unittest discover -s telemetry -p 'test_*.py' -v
node --test telemetry/test_replay.js
```

Las pruebas usan carpetas temporales y cubren importación tras reinicio, duplicados, escritura parcial, errores de formato, distancias sin enemigos ni saltos entre intentos, un directorio externo, endpoints, archivos privados y exportación.

Para importar los diarios pendientes sin abrir un servidor:

```sh
python3 telemetry/server.py --import-only
```

# Resonance of the Dark — partidas, SQLite y escenas editables

Este proyecto conserva el cementerio en primera persona de la rama `edit`: sus cuatro niveles, movimiento, sigilo, escondites, enemigos, salud, tiempo, rituales y progresión. El mapa guardado procede del generador original, con semillas 1401–1404. La distribución queda fija para que se pueda editar y para comparar los recorridos de distintas partidas.

## Jugar y consultar partidas

1. Abre `project.godot` con **Godot 4.7 o posterior** y espera la importación de los recursos.
2. Pulsa **F5**. Puedes escribir un alias; si lo dejas vacío se usa «Visitante».
3. **JUGAR** conserva la introducción. **SALTAR MENÚ** entra directamente en la misma partida. Las introducciones también tienen un botón para saltarlas.
4. Abre **http://127.0.0.1:8765/** para consultar el archivo local. Al comenzar una partida, el juego intenta iniciar este servidor con Python 3.

También puedes iniciar la web antes de jugar, desde la raíz del repositorio:

```sh
python3 telemetry/server.py
```

En macOS puedes ejecutar `Abrir_panel.command`. Se necesita **Python 3.9 o posterior**; el servidor usa únicamente la biblioteca estándar, sin instalación de paquetes. El servidor permanece disponible después de cerrar el juego. Si ya estaba iniciado, abre la misma dirección. Para detener un servidor iniciado en una terminal, usa Ctrl+C.

La página permite seleccionar una partida, filtrar por nivel e intento, reproducir el recorrido sobre un plano del cementerio, revisar la cronología y descargar los eventos en CSV o JSON. Se actualiza automáticamente mientras juegas. Las posiciones de los enemigos se registran como eventos y no se suman a la ruta del jugador.

En las partidas nuevas se registra **la posición y orientación de cada enemigo cada 0,5 segundos**, junto a su estado de patrulla, investigación o persecución. En la reproducción aparecen como **E1, E2…**, con colores y una lista que identifica a cada uno. Puedes ocultar sus marcadores. El mapa sigue el nivel e intento correspondiente al instante reproducido y la pausa detiene las muestras.

Al esconderte, el marcador del jugador cambia a azul y muestra **OCULTO**. La barra bajo la reproducción señala los intervalos ocultos y el recorrido usa un trazo distinto. Las transiciones se registran aunque no camines, incluida la breve salida física del escondite y las zonas de ocultación. Las partidas antiguas conservan sus registros; las posiciones enemigas que no se grabaron entonces no se pueden reconstruir.

## Qué se guarda y dónde

- **SQLite:** `telemetry/data/resonance.sqlite3`. Se crea automáticamente al iniciar el servidor.
- **Esquema:** `telemetry/schema.sql`, con tablas `sessions`, `events` e `ingestion_sources`.
- **Diario duradero:** `telemetry/data/spool/<partida>.jsonl`. El juego escribe y vacía el archivo después de cada evento; funciona aunque la web esté cerrada. El servidor importa las nuevas líneas en SQLite sin duplicarlas.
- **Identificación:** cada partida tiene su propio ID, alias opcional, fecha, duración y resultado. Cada entrada de nivel incrementa el número de intento.
- **Recorrido:** una muestra cada 0,5 segundos si el jugador se desplaza; en reposo, como máximo tres segundos entre muestras. El plano es una vista X/Z con los obstáculos y altares del nivel. La distancia es una aproximación a partir de esas muestras.
- **Acciones:** inicio/salto de menú e introducciones, daño, curación, muerte, correr, agacharse, saltar, ocultarse, recoger objetos/calabazas/cráneos, cargar y entregar restos, activar altares, completar misiones, abrir el portón, cambiar de nivel, pausa y salida. También diálogos, memorias y eventos ambientales.

Si se cierra el juego abruptamente, las entradas ya escritas permanecen y la web muestra la sesión como inactiva cuando deja de recibir datos. El registro describe lo ocurrido; **no es un sistema para continuar una partida guardada**.

Todo se encuentra dentro de esta carpeta del repositorio. El código, escenas y esquema se versionan; los diarios personales, la SQLite y sus archivos auxiliares están excluidos mediante `.gitignore`. Puedes respaldar `telemetry/data/` para conservar el historial. No hay envíos a un servicio externo de analítica del juego: este archivo escucha solamente en el equipo local.

Una exportación empaquetada escribe su diario en `user://telemetry/spool`, porque `res://` deja de ser una carpeta modificable. Para consultarla, ejecuta el servidor de este repositorio con `--spool-dir "ruta/al/spool"`. En el proyecto abierto desde Godot se usa siempre la carpeta `telemetry/data/spool`.

## Añadidos narrativos opcionales

Cada nivel incluye dos voces del cementerio, dos memorias y dos encuentros ambientales. Las historias conectan con Lucía y La Última Luz. No otorgan ventajas ni cambian los requisitos de las misiones, enemigos, colisiones o tiempos. Los NPC son apariciones sin colisión para que no bloqueen los pasillos.

**G** permite hablar o recoger una memoria cercana. Esta tecla es independiente de **F** (recoger objetos/calabazas), **T** (restos rituales), **E** (esconderse), **Q** (altares) y **R** (cráneos curativos), que conservan su función original. La conversación deja continuar el movimiento y el tiempo de la partida.

Al esconderse, la cámara baja suavemente, se recoge hacia la cobertura, se estabiliza con un movimiento sutil y se incorpora al salir. La oscuridad de los bordes también entra y sale gradualmente. Las animaciones `hide_enter`, `hide_hold` y `hide_exit` se editan en el nodo `HidingAnimation` del jugador; las capas visuales separan esta postura de las sacudidas de daño y del movimiento del ratón. La detección, los cinco segundos de respiración y la salida del escondite mantienen las reglas existentes.

## Editar desde Godot

Abre una escena, selecciona un nodo en el árbol y cambia sus propiedades en el Inspector. Para editar dentro de una instancia, usa clic derecho → **Hijos editables**, o abre su escena de origen. Guarda con Cmd+S/Ctrl+S y ejecuta el proyecto con F5.

| Elemento | Escena o nodo |
|---|---|
| Cementerios completos | `scenes/Level_01.tscn` a `Level_04.tscn` |
| Suelo, árboles, lápidas, muros y colisiones | `NavigationRegion3D/Environment` dentro del nivel |
| Escondites | `NavigationRegion3D/HidingZones` y objetos con grupo `hide_objects` |
| Coleccionables existentes | `NavigationRegion3D/Items` |
| Altares y salida | `RitualAltars` y `ExitGate` |
| Enemigos y patrullas | `Enemy`, `Enemy2`… y `PatrolPoints`; los puntos son `Marker3D` |
| Reaparición de cráneos | `HealthRespawnPoints`, puntos editables |
| Jugador, cámara, hitbox, animación, radar y objetivos | `scenes/actors/Player.tscn` |
| Menú y botón para saltarlo | `scenes/MainMenu.tscn` |
| Pausa, fin de partida e introducciones | `scenes/ui/` |
| Tiempo y puntuación | `scenes/ui/LevelManager.tscn` |
| NPC, diálogos, memorias y eventos | `scenes/narrative/Narrative_01.tscn` a `Narrative_04.tscn` |
| Modelos y textos reutilizables de NPC/memorias | `scenes/narrative/Keeper.tscn`, `Memory.tscn` |
| Sonido y parpadeo de encuentros | `scenes/narrative/AmbientEncounter.tscn`, `AnimationPlayer/echo` |
| Intervalo de registro, activación y puerto web | `scenes/systems/GameplayLog.tscn`, autoload `GameplayLog` |

Mueve la raíz completa de un objeto para llevar su modelo y su colisión juntos. Las escenas guardadas son la fuente de las posiciones: al jugar no se reconstruye el mapa ni se sobreescriben sus transformaciones. Se recalcula la navegación para respetar los obstáculos editados. Los efectos y elementos que aparecen durante una partida instancian escenas guardadas.

La lógica permanece en GDScript. `LevelBuilder.gd` conserva el generador original para trabajo de autoría, pero las cuatro escenas usan `auto_build_on_ready = false` y enlazan los nodos guardados. Activar deliberadamente ese generador reemplaza el diseño guardado en la ejecución; para editar normalmente, deja desactivada esa opción.

| Nivel | Enemigos | Altares | Calabazas | Restos rituales |
|---|---:|---:|---:|---:|
| 1 | 2 | 2 | 0 | 0 |
| 2 | 3 | 4 | 0 | 0 |
| 3 | 3 | 4 | 7 | 0 |
| 4 | 4 | 4 | 4 | 2 |

## Verificación

Las pruebas del mundo y de la interfaz comprueban que guardar/recargar nodos conserve sus propiedades, colisiones e interacciones y que los controles originales sigan funcionando. La prueba integrada abre el menú, inicia una partida, mueve al jugador y comprueba el diario que producen las acciones reales.

```sh
RESONANCE_CAPTURE=1 godot --headless --path . --script tests/authored_world.gd
RESONANCE_CAPTURE=1 godot --headless --path . --script tests/editable_player_ui.gd
RESONANCE_CAPTURE=1 godot --headless --path . --script tests/hiding_animation.gd
RESONANCE_DISABLE_WEB=1 RESONANCE_LOG_DIR=/tmp/resonance-test-spool godot --headless --path . --script tests/telemetry_gameplay.gd
RESONANCE_DISABLE_WEB=1 RESONANCE_LOG_DIR=/tmp/resonance-enemies-test-spool godot --headless --path . --script tests/telemetry_enemy_replay.gd
python3 -m unittest discover -s telemetry -p 'test_*.py' -v
node --test telemetry/test_replay.js
```

En macOS, si `godot` no está en el PATH, utiliza `/Applications/Godot.app/Contents/MacOS/Godot`. `RESONANCE_CAPTURE=1` desactiva los registros durante las pruebas visuales; no debe usarse al jugar si quieres guardar la partida. Las pruebas de SQLite usan directorios temporales y no alteran las partidas reales.

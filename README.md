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

El código, las escenas y el esquema se versionan; los diarios personales y la SQLite local están excluidos mediante `.gitignore`. La copia local del panel escucha en este equipo y sirve como respaldo. Además, el juego sincroniza eventos con la Edge Function de Supabase configurada en `GameplayLog.tscn`: intenta subirlos cada 15 segundos, en lotes de hasta 50 eventos. Si la red falla, mantiene los diarios locales y vuelve a intentar el envío. El historial central y las cuentas/partidas guardadas son funciones distintas; las partidas registradas no se pueden reanudar desde el diario.

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

## 🕹️ Mecánicas de Game Feel y Juice

Para mejorar la responsividad, la fluidez y la retroalimentación visual del jugador, se implementaron cuatro elementos clave de *Game Feel*:

### 1. Input Buffering (Salto)
Permite almacenar temporalmente la orden de salto antes de tocar el suelo para ejecutarla inmediatamente al aterrizar.
* **Ventana de almacenamiento (`jump_buffer_time`):** `0.15 segundos` (150 ms)
* **Comportamiento:** Previene la pérdida de pulsaciones si el jugador presiona el botón ligeramente antes de tocar la superficie.

### 2. Coyote Time
Otorga un margen de gracia para saltar tras haber dejado el borde de una plataforma.
* **Tiempo de gracia (`coyote_time`):** `0.15 segundos` (150 ms)
* **Comportamiento:** Mantiene activo el estado de "en suelo" durante una fracción de segundo en el aire para evitar caídas no intencionadas.

### 3. Screenshake (Vibración de Cámara)
Sistema dinámico de vibración localizado en `Player.gd` para enfatizar las acciones y el impacto.
* **Disminución gradual (`shake_decay`):** `5.0`
* **Intensidades por evento:**
  - **Caminar:** `0.01` (Micro-vibración sutil)
  - **Correr:** `0.03` (Vibración continua moderada)
  - **Aterrizaje:** `0.15` (Impacto seco al tocar piso)
  - **Daño Recibido:** `0.40` (Sacudida fuerte e inmediata)

### 4. Direct Feedback y Movimiento
* **Head Bobbing & Weight:** Balanceo sinusoidal de cámara en ejes X/Y y rotación Z (`walk_step_frequency: 12.0`, `run_step_frequency: 16.0`) para eliminar la sensación de flotación al desplazarse.
* **Mecánica de Escondite:** Reducción/bloqueo parcial de vista, temporizador en HUD (*Aguantando la respiración: 5...*) e inmunidad temporal ante enemigos.
* **Transiciones y Menús:** Soporte de salto directo de pantallas intermadias mediante la tecla `ENTER`.


## 📱 Adaptación a Dispositivos Móviles (Práctica 6)

[Repositorio público: rama `practica-6`](https://github.com/abrahambravo1416/resonance-of-the-dark/tree/practica-6), continuada desde `main` (`fe6db5c`), con los guardados, cuentas, puntuaciones, SQLite, recorridos y panel web existentes. La capa de entrada unificada envía movimiento, cámara y acciones al **Input Map**. Teclado, gamepad y táctil conviven: soltar el joystick conserva una tecla o un stick físico que siga pulsado. El personaje conserva sus ventanas de **Input Buffering y Coyote Time de 0,15 s**, screenshake y feedback.

### Parámetros de Configuración Táctil

| Parámetro | Valor de referencia | Configuración implementada |
| :--- | :--- | :--- |
| Radio del joystick | 80–120 px | 100 px por defecto, escalable |
| Zona muerta del joystick | 0.05–0.35 | 0.15 por defecto, ajustable |
| Tamaño mínimo de botones de acción | ≥ 96 px | 108 × 108 px; mínimo ajustable 97.2 px |
| Tamaño de controles | 90–150% | 100% por defecto, ajustable |
| Opacidad | 10–100% | 40% por defecto, ajustable |
| Velocidad de giro táctil | 50–200% | 130% por defecto, ajustable |
| Vibración común | Un pulso corto | 120 ms efectivos para pausa, recolección, altar y daño |
| Vibración intensa | Patrón de varios pulsos | 3 pulsos de 240 ms al morir o completar el nivel |
| Orientación y stretch | Landscape, canvas_items + expand | Landscape, `canvas_items`, `expand`, referencia 1280 × 720 |

Son píxeles lógicos del viewport; su tamaño físico depende de la pantalla. El ajuste **Tamaño** permite compensarlo. La equivalencia a 9 mm y la vibración requieren comprobación en el dispositivo final.

### Uso y escenas editables

- Pulgar izquierdo: joystick inferior izquierdo. Pulgar derecho: deslizar en la zona central derecha para mirar; **Saltar**, **Correr** y **Agachar** en la esquina inferior derecha. **Pausa** arriba.
- **Interacción dinámica estilo Minecraft PE:** un botón contextual muestra la acción disponible: esconderse/salir, recoger, encender altar, llevar restos o hablar/recordar. El portón abierto se cruza caminando, como antes.
- **Multitouch:** cada dedo mantiene su índice hasta liberarse, incluso si sale del área. Movimiento, cámara y botones son independientes. Pausar, ocultar el HUD o perder foco libera la entrada virtual.
- **Safe area:** los márgenes físicos de `DisplayServer.get_display_safe_area()` se convierten a coordenadas del viewport al cambiar de tamaño. El radar se sitúa por encima del joystick.
- **Ajustes:** botón **Controles** en el menú principal o dentro del menú de pausa. Opacidad, tamaño, zona muerta, velocidad de giro táctil (50–200%) y vibración se guardan en `user://touch_controls.cfg`; **Restablecer predeterminado** recupera el perfil inicial (40% de opacidad, 100% de tamaño, 130% de giro y zona muerta 0.15).
- **Vibración:** **Probar** envía tres pulsos de 240 ms. En juego se solicita un pulso común en pausa, al recoger objetos/restos o cráneos, encender un altar y recibir daño; morir o escapar usa tres pulsos intensos. El script limita los pulsos comunes a 120 ms y los intensos a 240 ms, con amplitud máxima solicitada. El preset Android actual incluye `VIBRATE`; hay que volver a exportar e instalar el APK tras cambiar permisos. La sensación final depende del motor háptico y los ajustes del teléfono.
- **Depuración en PC:** activa **Probar táctil en PC** en Controles durante una ejecución de depuración, o usa `RESONANCE_TOUCH_DEBUG=1`. El ajuste está desactivado por defecto y el botón **Restablecer predeterminado** vuelve a desactivarlo. `Emulate Touch From Mouse` está habilitado. [Godot también considera la emulación como disponibilidad táctil](https://docs.godotengine.org/en/stable/classes/class_displayserver.html#class-displayserver-method-is-touchscreen-available); se distingue del dispositivo físico para que el HUD siga oculto en PC sin activar la prueba. Un mouse representa un dedo; las pruebas automatizadas inyectan índices separados para verificar multitouch.
- Gamepad: stick izquierdo mueve, derecho mira; A salta, LB corre, B agacha, X recoge, Y esconde, Start pausa. Cruceta: arriba narrativa, izquierda altar, abajo curación, derecha restos.

Los archivos principales son `scripts/VirtualJoystick.gd`, `scripts/TouchHUD.gd`, `scripts/UnifiedInput.gd`, `scripts/ControlSettings.gd` y `scenes/ui/TouchHUD.tscn`. Los botones son nodos `TouchScreenButton` editables; sus acciones son `ui_accept`, `sprint`, `crouch`, `ui_cancel` y la interacción correspondiente. `VirtualJoystick` también funciona de forma independiente, usando directamente `Input.action_press/action_release` si no existe el mezclador.

### Limitaciones y acceso a la interfaz web desde móviles

En la computadora que guarda SQLite ejecuta:

```sh
python3 telemetry/server.py --host 0.0.0.0 --port 8765
```

Desde un teléfono de la misma red abre `http://IP_DE_LA_COMPUTADORA:8765`. La opción anterior permite a los equipos de esa red consultar el archivo de partidas, sin autenticación; úsala en una red de confianza. El inicio normal sigue escuchando solo en `127.0.0.1`. El firewall y el aislamiento entre clientes del Wi-Fi pueden impedir el acceso.

En el celular, `localhost` identifica al propio teléfono. El juego móvil no intenta arrancar Python: conserva el diario en `user://telemetry/spool`. Para verlo en SQLite debes copiar esos diarios a la computadora o usar la sincronización remota existente, cuando esté configurada. Las cuentas y guardados remotos siguen necesitando conectividad. Esta adaptación no cambia sus credenciales ni servicios.

En pantallas estrechas la tabla de comparación de intentos usa desplazamiento horizontal. La clasificación y los datos remotos dependen del servicio ya configurado; las pruebas de esta entrega no iniciaron sesión ni escribieron en cuentas reales.

### Evidencias y verificación

- [Controles en juego](capturas/practica-6/controles.png)
- [Menú de ajustes](capturas/practica-6/ajustes.png)
- [HUD móvil](capturas/practica-6/hud-movil.png)
- [Video de demostración](capturas/practica-6/demo-tactil.mp4)

**Entorno verificado:** Godot 4.7.2 en Windows; controles táctiles y multitouch también se comprueban con pruebas automatizadas. Se exportó e instaló una APK en un Samsung SM-S938B y se verificó que las sesiones móviles llegaran a Supabase con plataforma `mobile`. La vibración está implementada y el preset declara `VIBRATE`, pero no se considera validada como perceptible de forma consistente: compruébala con **Probar** y con los ajustes hápticos del teléfono. El APK se genera localmente desde el preset Android y no se incluye en el repositorio.

```sh
RESONANCE_CAPTURE=1 RESONANCE_DISABLE_WEB=1 godot --headless --path . --script tests/mobile_controls.gd
python3 -m unittest discover -s telemetry -p 'test_*.py' -v
node --test telemetry/test_replay.js
```

La prueba táctil comprueba zona muerta, multitouch, liberación fuera del área, buffer y coyote en una plataforma física, cámara, teclado simultáneo, safe area, contexto, pausa, persistencia de ajustes, progreso, puntuación y screenshake. Usa un perfil Godot separado al ejecutarla (duplica el proyecto y cambia temporalmente `application/config/name` en `project.godot` antes de abrir la copia): modifica únicamente el estado de la partida de prueba y escribe su configuración de prueba en `user://mobile_test_controls.cfg` (o la ruta de `RESONANCE_CONTROL_CONFIG`). Para volver a grabar las evidencias, usa `tools/capture_mobile.gd` con `--write-movie` y `--fixed-fps 30`; `RESONANCE_MOBILE_VIDEO=1` añade la plataforma visual de prueba. `RESONANCE_CAPTURE_DIR` selecciona la carpeta de capturas (por defecto, `user://mobile_captures`).

Resultados locales: **27 comprobaciones táctiles**, **40 de escondite/cámara**, **14 pruebas Python de SQLite/HTTP** y **8 de reproducción JavaScript**, sin fallos. Las escenas de los cuatro niveles y sus reglas se conservan.

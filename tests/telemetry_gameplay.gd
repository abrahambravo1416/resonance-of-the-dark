extends SceneTree
## Partida automatizada real: usa los mismos botones e interacciones que el juego.
## Ejecutar con RESONANCE_LOG_DIR temporal y RESONANCE_DISABLE_WEB=1.

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var logger: Node = root.get_node("GameplayLog")
	logger.enabled = true
	logger.launch_local_dashboard = false
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await process_frame
	await process_frame
	current_scene.get_node("MenuLayout/PlayerAlias").text = "Verificación automática"
	current_scene.get_node("MenuLayout/SkipMenuButton").pressed.emit()
	for tick in range(10):
		await process_frame
	var level: Node3D = current_scene
	var player: CharacterBody3D = level.get_node("Player")
	for enemy in level.enemies:
		enemy.set_physics_process(false)
	check(not paused and not player.controls_frozen, "Skip del menú abre la misma partida jugable")
	check(not logger.session_id.is_empty(), "Partida abre registro duradero")
	var path: String = logger.log_path
	var session: String = logger.session_id
	var starting_position := player.global_position
	Input.action_press("move_forward")
	for tick in range(66):
		await physics_frame
	Input.action_release("move_forward")
	check(player.global_position.distance_to(starting_position) > 1.0, "Movimiento real con entrada WASD")
	var health_before: int = player.current_health
	player.take_damage(1)
	check(player.current_health == health_before - 1, "Daño original se conserva")
	player.heal(1)
	check(player.current_health == health_before, "Curación original se conserva")
	var keeper: Node3D = level.get_node("Narrative/Custodian")
	player.global_position = keeper.global_position + Vector3(0, 1, 1.6)
	player.velocity = Vector3.ZERO
	await process_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(level.get_node("Narrative/NarrativeHUD/Dialogue").visible, "NPC abre diálogo opcional")
	check(player.current_health == health_before and player.rituals_completed == 0, "NPC no altera vida ni misiones")
	var memory: Node3D = level.get_node("Narrative/FirstMemory")
	player.global_position = memory.global_position + Vector3(0, 1, 0.8)
	player.velocity = Vector3.ZERO
	await process_frame
	Input.parse_input_event(key)
	await process_frame
	check(memory.collected and not memory.visible, "Memoria se recoge por interacción")
	var encounter: Area3D = level.get_node("Narrative/PassingEcho")
	encounter._on_body_entered(player)
	check(encounter.triggered, "Evento ambiental se activa")
	var item: Node3D = level.items_root.get_children().filter(func(node): return node is InteractableItem)[0]
	item.interact(player)
	await process_frame
	check(player.items_collected == 1, "Coleccionable original conserva su efecto")
	level.get_node("PauseMenu")._toggle_pause()
	await process_frame
	check(paused, "Pausa original funciona")
	level.get_node("PauseMenu")._resume_game()
	await process_frame
	check(not paused, "Reanudar original funciona")
	root.get_node("GameManager").skip_next_intro = true
	reload_current_scene()
	for tick in range(10):
		await process_frame
	check(logger.session_id == session and logger.attempt == 2, "Reintentar conserva sesión y crea intento nuevo")
	root.get_node("GameManager").skip_next_intro = true
	change_scene_to_file("res://scenes/Level_02.tscn")
	for tick in range(10):
		await process_frame
	check(logger.session_id == session and logger.current_level == 2 and logger.attempt == 3, "Cambiar nivel conserva historial y separa recorrido")
	logger.end_session("verification_complete")
	for tick in range(3):
		await process_frame
	check(logger.session_id.is_empty(), "Cerrar sesión no genera otra partida fantasma")
	var kinds: Dictionary = {}
	var ids: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	var expected_sequence := 1
	var level_starts := 0
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var event: Dictionary = JSON.parse_string(line)
		check(event.session_id == session and int(event.seq) == expected_sequence, "Diario ordenado y aislado por partida")
		expected_sequence += 1
		check(not ids.has(event.event_id), "Identificador de evento único")
		ids[event.event_id] = true
		kinds[event.kind] = int(kinds.get(event.kind, 0)) + 1
		if event.kind == "level_started":
			level_starts += 1
		if int(event.level) > 0:
			check(int(event.data.attempt) == level_starts, "Eventos pertenecen al intento correcto desde la introducción")
	file.close()
	check(level_starts == 3, "Exactamente un evento de inicio por nivel o reintento")
	for kind in ["session_started", "menu_skipped", "level_started", "position_sample", "damage_taken", "health_restored", "npc_dialogue", "memory_collected", "ambient_event", "item_collected", "paused", "resumed", "session_ended"]:
		check(kinds.has(kind), "Registro incluye %s" % kind)
	print("TELEMETRY_GAMEPLAY: %d checks, %d failures; spool=%s" % [checks, failures.size(), path])
	logger.enabled = false
	current_scene.free()
	current_scene = null
	await process_frame
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

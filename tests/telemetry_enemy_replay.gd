extends SceneTree
## Comprueba recorridos de los enemigos reales sin mover al jugador.
## Ejecutar con RESONANCE_LOG_DIR=/private/tmp/... y RESONANCE_DISABLE_WEB=1.

var checks: int = 0
var failures: Array[String] = []
var log_path: String = ""


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)


func events_of(kind: String = "") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return events
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var event: Dictionary = JSON.parse_string(line)
		if kind.is_empty() or event.kind == kind:
			events.append(event)
	file.close()
	return events


func position_of(event: Dictionary) -> Vector3:
	return Vector3(float(event.position.x), float(event.position.y), float(event.position.z))


func sample_and_check(logger: Node, level: Node) -> void:
	var before: int = events_of("enemy_position_sample").size()
	logger._process(logger.sample_interval)
	var samples := events_of("enemy_position_sample")
	check(samples.size() == before + level.enemies.size(), "Cada muestra incluye todos los enemigos del nivel")
	for index in range(before, samples.size()):
		var event: Dictionary = samples[index]
		var enemy := level.get_node_or_null(NodePath(event.data.enemy_id)) as Node3D
		check(enemy != null, "El ID estable resuelve al enemigo guardado en la escena")
		if enemy == null:
			continue
		check(position_of(event).is_equal_approx(enemy.global_position), "Posición registrada coincide con el transform global real")
		check(is_equal_approx(float(event.data.yaw), enemy.global_rotation.y), "Orientación registrada coincide con el enemigo")
		check(event.data.state in ["patrol", "investigate", "chase"], "Estado del enemigo usa valores de reproducción conocidos")
		check(int(event.level) == logger.current_level and int(event.data.attempt) == logger.attempt, "Cada enemigo queda separado por nivel e intento")


func _run() -> void:
	var logger: Node = root.get_node("GameplayLog")
	logger.enabled = true
	logger.launch_local_dashboard = false
	logger.set_process(false)
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await process_frame
	await process_frame
	current_scene.get_node("MenuLayout/PlayerAlias").text = "Verificación de enemigos"
	current_scene.get_node("MenuLayout/SkipMenuButton").pressed.emit()
	for tick in range(10):
		await process_frame
	var level: Node3D = current_scene
	var player: CharacterBody3D = level.get_node("Player")
	player.set_physics_process(false)
	var stationary_position := player.global_position
	log_path = logger.log_path
	var session: String = logger.session_id
	check(not paused and logger.attempt == 1, "La partida comienza sin pausa en el primer intento")
	check(level.enemies.size() == 2, "Se conserva la población original del primer nivel")
	var foreign_enemy := Node3D.new()
	foreign_enemy.name = "EnemyOutsideCurrentLevel"
	root.add_child(foreign_enemy)
	foreign_enemy.add_to_group("enemy")
	var starts: Dictionary = {}
	for enemy in level.enemies:
		starts[str(level.get_path_to(enemy))] = enemy.global_position
	sample_and_check(logger, level)
	for tick in range(150):
		await physics_frame
		if tick % 30 == 29:
			sample_and_check(logger, level)
	check(player.global_position.is_equal_approx(stationary_position), "El jugador permanece inmóvil durante el recorrido enemigo")
	var tracks: Dictionary = {}
	var moving_tracks: Dictionary = {}
	for sample in events_of("enemy_position_sample"):
		var enemy_id: String = sample.data.enemy_id
		tracks[enemy_id] = int(tracks.get(enemy_id, 0)) + 1
		check(starts.has(enemy_id), "Ningún enemigo ajeno al nivel entra al recorrido")
		if starts.has(enemy_id) and position_of(sample).distance_to(starts[enemy_id]) > 0.1:
			moving_tracks[enemy_id] = true
	check(tracks.size() == 2, "Los IDs de ambos enemigos permanecen estables entre muestras")
	check(moving_tracks.size() >= 1, "La IA patrulla realmente mientras el jugador está quieto")
	for enemy_id in tracks:
		check(int(tracks[enemy_id]) >= 6, "El enemigo sigue registrándose aunque el jugador no camine")
	for sample in events_of("position_sample"):
		check(position_of(sample).is_equal_approx(stationary_position), "Las posiciones enemigas no contaminan el recorrido del jugador")
		check(not sample.data.has("enemy_id"), "El recorrido del jugador conserva su tipo independiente")
	var before_pause: int = events_of("enemy_position_sample").size()
	paused = true
	logger._process(2.0)
	logger._process(2.0)
	check(events_of("enemy_position_sample").size() == before_pause, "La pausa detiene las muestras de enemigos")
	check(events_of("paused").size() == 1, "La pausa se registra una sola vez")
	paused = false
	sample_and_check(logger, level)
	check(events_of("resumed").size() == 1, "Reanudar restaura la grabación y registra el cambio")
	var removed_enemy: Node3D = level.enemies[0]
	var removed_id := str(level.get_path_to(removed_enemy))
	removed_enemy.queue_free()
	logger._sample_enemies(level)
	await process_frame
	logger._sample_enemies(level)
	logger._sample_enemies(level)
	var removals := events_of("enemy_removed")
	check(removals.size() == 1 and removals[0].data.enemy_id == removed_id, "La desaparición de un enemigo se registra una sola vez")
	foreign_enemy.free()
	root.get_node("GameManager").skip_next_intro = true
	reload_current_scene()
	for tick in range(10):
		await process_frame
	level = current_scene
	level.get_node("Player").set_physics_process(false)
	check(logger.session_id == session and logger.attempt == 2, "Reintentar conserva la sesión y separa las pistas enemigas")
	sample_and_check(logger, level)
	check(events_of("enemy_removed").size() == 1, "Cambiar de intento no produce bajas fantasma")
	var fresh_ids: Dictionary = {}
	for event in events_of("enemy_position_sample"):
		if int(event.data.attempt) == 2:
			fresh_ids[event.data.enemy_id] = true
	check(fresh_ids.size() == 2 and fresh_ids.has(removed_id), "El nuevo intento recupera la población con IDs válidos")
	logger.end_session("verification_complete")
	logger._process(2.0)
	check(logger.session_id.is_empty(), "Cerrar el registro no crea una sesión fantasma")
	var expected_sequence := 1
	var ids: Dictionary = {}
	for event in events_of():
		check(int(event.seq) == expected_sequence and not ids.has(event.event_id), "Los eventos conservan secuencia e identificador únicos")
		ids[event.event_id] = true
		expected_sequence += 1
	print("TELEMETRY_ENEMY_REPLAY: %d checks, %d failures; spool=%s" % [checks, failures.size(), log_path])
	logger.enabled = false
	current_scene.free()
	current_scene = null
	await process_frame
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

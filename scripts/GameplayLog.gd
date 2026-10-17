extends Node
## Registro local duradero. El servidor web importa este diario en SQLite.
## Se mantiene activo en pausa para cerrar correctamente la sesión.

@export var enabled: bool = true
@export_range(0.1, 5.0, 0.1) var sample_interval: float = 0.5
@export var minimum_sample_distance: float = 0.12
@export var launch_local_dashboard: bool = true
@export var dashboard_port: int = 8765

var session_id: String = ""
var current_level: int = 0
var attempt: int = 0
var log_path: String = ""
var _file: FileAccess
var _sequence: int = 0
var _started_ticks: int = 0
var _sample_time: float = 0.0
var _last_sample_elapsed: float = -10.0
var _last_position: Vector3 = Vector3.INF
var _scene_id: int = 0
var _was_paused: bool = false
var _enemy_states: Dictionary = {}
var _enemy_names: Dictionary = {}
var _web_started: bool = false
var _closing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("RESONANCE_CAPTURE") == "1":
		enabled = false
	if enabled:
		get_tree().auto_accept_quit = false


func start_session(player_name: String = "Visitante") -> void:
	if not enabled:
		return
	if not session_id.is_empty():
		end_session("new_run")
	var spool_dir := _spool_directory()
	var result := DirAccess.make_dir_recursive_absolute(spool_dir)
	if result != OK:
		push_error("No se pudo crear el registro de partidas: %s" % spool_dir)
		return
	var random_id := Crypto.new().generate_random_bytes(12).hex_encode()
	session_id = "%d_%s" % [int(Time.get_unix_time_from_system()), random_id]
	log_path = spool_dir.path_join(session_id + ".jsonl")
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_error("No se pudo guardar la partida en %s" % log_path)
		session_id = ""
		return
	_started_ticks = Time.get_ticks_msec()
	_sequence = 0
	current_level = 0
	attempt = 0
	_scene_id = 0
	_last_position = Vector3.INF
	_last_sample_elapsed = -10.0
	_sample_time = 0.0
	_was_paused = false
	_enemy_states.clear()
	_enemy_names.clear()
	record("session_started", {"player_name": player_name.strip_edges().left(60) if not player_name.strip_edges().is_empty() else "Visitante", "game_version": "resonance-local-2", "position_interval_seconds": sample_interval, "enemy_position_interval_seconds": sample_interval})
	_start_local_dashboard()


func end_session(outcome: String = "quit") -> void:
	if session_id.is_empty():
		return
	record("session_ended", {"outcome": outcome})
	_file.close()
	_file = null
	session_id = ""
	current_level = 0


func record(kind: String, data: Dictionary = {}, position: Variant = null, level: int = -1) -> void:
	if not enabled or _file == null or session_id.is_empty():
		return
	_sequence += 1
	var details := data.duplicate(true)
	details["attempt"] = attempt
	var event := {
		"event_id": "%s:%d" % [session_id, _sequence],
		"session_id": session_id, "seq": _sequence, "kind": kind,
		"ts": Time.get_unix_time_from_system(),
		"elapsed": float(Time.get_ticks_msec() - _started_ticks) / 1000.0,
		"level": current_level if level < 0 else level, "data": details,
	}
	if position is Vector3:
		event["position"] = {"x": position.x, "y": position.y, "z": position.z}
	elif position is Dictionary:
		event["position"] = position
	_file.store_line(JSON.stringify(event))
	_file.flush()


func set_level(level: int, metadata: Dictionary = {}) -> void:
	if not enabled:
		return
	if session_id.is_empty():
		start_session()
	current_level = level
	attempt += 1
	_last_position = Vector3.INF
	_last_sample_elapsed = -10.0
	_sample_time = sample_interval
	_enemy_states.clear()
	_enemy_names.clear()
	record("level_started", metadata)


func observe_level(scene: Node) -> void:
	if not enabled or scene.get_instance_id() == _scene_id:
		return
	var level_value: int = int(scene.get("level_number"))
	var grid: Vector2i = scene.get("grid_size")
	var cell: float = float(scene.get("cell_size"))
	set_level(level_value, {
		"scene": scene.scene_file_path, "title": "Cementerio %d" % level_value,
		"map_bounds": {"min_x": -cell * 2.0, "max_x": float(grid.x) * cell, "min_z": -cell, "max_z": float(grid.y) * cell},
		"map_geometry": _map_geometry(scene),
	})
	_scene_id = scene.get_instance_id()


func _process(delta: float) -> void:
	if not enabled or _closing:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var level_value: Variant = scene.get("level_number")
	if level_value != null and scene.get_instance_id() != _scene_id:
		observe_level(scene)
	elif level_value == null and not session_id.is_empty() and current_level > 0:
		end_session("returned_to_menu")
	if session_id.is_empty():
		return
	if get_tree().paused != _was_paused:
		_was_paused = get_tree().paused
		record("paused" if _was_paused else "resumed")
	if get_tree().paused:
		return
	_sample_time += delta
	if _sample_time < sample_interval:
		return
	_sample_time = 0.0
	_sample_enemies(scene)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var elapsed := float(Time.get_ticks_msec() - _started_ticks) / 1000.0
	var moved := _last_position == Vector3.INF or player.global_position.distance_to(_last_position) >= minimum_sample_distance
	if moved or elapsed - _last_sample_elapsed >= 3.0:
		_last_position = player.global_position
		_last_sample_elapsed = elapsed
		var cover: Variant = player.get("_hiding_target")
		record("position_sample", {
			"running": bool(player.get("is_running")), "crouching": bool(player.get("is_crouching")),
			"hidden": bool(player.get("is_hiding")) or bool(player.get("is_hidden")),
			"hiding": bool(player.get("is_hiding")), "hidden_by_zone": bool(player.get("_hidden_by_zone")),
			"cover_type": str(player.get("current_cover_type")),
			"cover": str(cover.name) if is_instance_valid(cover) else "",
			"health": int(player.get("current_health")), "yaw": player.rotation.y,
		}, player.global_position)


func _sample_enemies(scene: Node) -> void:
	# Each actor has its own track. Never use these points for player distance.
	# The scene-relative path is stable across samples; level/attempt scopes it.
	var present: Dictionary = {}
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node3D or not scene.is_ancestor_of(enemy) or enemy.is_queued_for_deletion():
			continue
		var enemy_key := str(scene.get_path_to(enemy))
		present[enemy_key] = true
		_enemy_names[enemy_key] = str(enemy.name)
		var state: Variant = enemy.get("state")
		var states := ["patrol", "investigate", "chase"]
		var state_name: String = states[clampi(int(state), 0, 2)] if state != null else "unknown"
		var details := {"enemy_id": enemy_key, "enemy": str(enemy.name), "state": state_name, "yaw": enemy.global_rotation.y}
		if state != null and _enemy_states.get(enemy_key, -1) != int(state):
			_enemy_states[enemy_key] = int(state)
			record("enemy_state_changed", details, enemy.global_position)
		record("enemy_position_sample", details, enemy.global_position)
	for enemy_key in _enemy_names.keys():
		if not present.has(enemy_key):
			record("enemy_removed", {"enemy_id": enemy_key, "enemy": _enemy_names[enemy_key]})
			_enemy_names.erase(enemy_key)
			_enemy_states.erase(enemy_key)


func _spool_directory() -> String:
	var override := OS.get_environment("RESONANCE_LOG_DIR")
	if not override.is_empty():
		return override
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://telemetry/data/spool")
	return ProjectSettings.globalize_path("user://telemetry/spool")


func _start_local_dashboard() -> void:
	if _web_started or not launch_local_dashboard or OS.get_environment("RESONANCE_DISABLE_WEB") == "1":
		return
	var server := ProjectSettings.globalize_path("res://telemetry/server.py")
	if not FileAccess.file_exists(server):
		return
	var executable := "python" if OS.get_name() == "Windows" else "python3"
	var arguments := PackedStringArray([server, "--port", str(dashboard_port), "--spool-dir", _spool_directory()])
	var pid := OS.create_process(executable, arguments)
	_web_started = pid > 0
	if pid <= 0:
		push_warning("El diario de partida está guardado. Para consultar SQLite ejecuta: python3 telemetry/server.py")


func _map_geometry(scene: Node) -> Dictionary:
	var points: Array = []
	var altars: Array = []
	for node in scene.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.disabled or not shape_node.get_parent() is StaticBody3D:
			continue
		if not shape_node.shape is BoxShape3D:
			continue
		var size: Vector3 = (shape_node.shape as BoxShape3D).size * shape_node.global_basis.get_scale().abs()
		if size.y < 0.35 or size.x > 15.0 or size.z > 15.0:
			continue
		points.append({"x": shape_node.global_position.x, "z": shape_node.global_position.z, "width": size.x, "depth": size.z, "yaw": shape_node.global_rotation.y})
	for node in get_tree().get_nodes_in_group("ritual_altars"):
		altars.append({"x": node.global_position.x, "z": node.global_position.z, "name": node.name})
	return {"obstacles": points, "altars": altars}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and enabled:
		_closing = true
		end_session("window_closed")
		get_tree().quit()


func _exit_tree() -> void:
	end_session("application_closed")

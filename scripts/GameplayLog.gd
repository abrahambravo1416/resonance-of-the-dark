extends Node
## Registro local duradero. El servidor web importa este diario en SQLite.
## Se mantiene activo en pausa para cerrar correctamente la sesión.

@export var enabled: bool = true
@export_range(0.1, 5.0, 0.1) var sample_interval: float = 0.5
@export var minimum_sample_distance: float = 0.12
@export var launch_local_dashboard: bool = true
@export var dashboard_port: int = 8765
## La URL de la Edge Function y la clave publishable son configuración pública del cliente.
## La clave secret/service_role nunca debe colocarse aquí ni distribuirse con el juego.
@export var remote_ingest_url: String = ""
@export var remote_publishable_key: String = ""
@export_range(5.0, 120.0, 1.0) var remote_upload_interval: float = 15.0
@export_range(1, 100, 1) var remote_batch_size: int = 50

var session_id: String = ""
var player_id: String = ""
var player_name: String = "Invitado"
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
var _upload_request: HTTPRequest
var _upload_timer: Timer
var _upload_offsets: Dictionary = {}
var _pending_upload_offsets: Dictionary = {}
var _upload_in_flight: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_player_profile()
	_upload_request = HTTPRequest.new()
	_upload_request.timeout = 20.0
	_upload_request.request_completed.connect(_on_upload_completed)
	add_child(_upload_request)
	_upload_timer = Timer.new()
	_upload_timer.wait_time = maxf(remote_upload_interval, 5.0)
	_upload_timer.timeout.connect(_upload_pending_logs)
	add_child(_upload_timer)
	_load_upload_offsets()
	_upload_timer.start()
	if OS.get_environment("RESONANCE_CAPTURE") == "1":
		enabled = false
	if enabled:
		get_tree().auto_accept_quit = false


func start_session(requested_player_name: String = "") -> void:
	if not enabled:
		return
	var resolved_player_name := requested_player_name.strip_edges()
	if resolved_player_name.is_empty():
		var account := get_node_or_null("/root/CloudAccount")
		if account != null and bool(account.get("is_authenticated")):
			resolved_player_name = str(account.get("username")).strip_edges()
	if resolved_player_name.is_empty():
		resolved_player_name = "Invitado"
	set_player_name(resolved_player_name)
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
	record("session_started", {"player_id": player_id, "player_name": player_name, "game_version": "resonance-local-3", "position_interval_seconds": sample_interval, "enemy_position_interval_seconds": sample_interval})
	_start_local_dashboard()


func get_player_id() -> String:
	return player_id


func get_player_name() -> String:
	return player_name


func set_player_name(value: String) -> void:
	var cleaned_name := value.strip_edges().left(48)
	player_name = cleaned_name if not cleaned_name.is_empty() else "Invitado"
	_save_player_profile()


func _load_player_profile() -> void:
	var profile := ConfigFile.new()
	if profile.load("user://player_profile.cfg") == OK:
		player_id = str(profile.get_value("profile", "player_id", ""))
		player_name = str(profile.get_value("profile", "player_name", "Invitado")).strip_edges().left(48)
	if player_id.is_empty():
		player_id = Crypto.new().generate_random_bytes(16).hex_encode()
	if player_name.is_empty() or player_name.to_lower() == "visitante":
		player_name = "Invitado"
	_save_player_profile()


func _save_player_profile() -> void:
	var profile := ConfigFile.new()
	profile.set_value("profile", "player_id", player_id)
	profile.set_value("profile", "player_name", player_name)
	var error := profile.save("user://player_profile.cfg")
	if error != OK:
		push_warning("No se pudo guardar el perfil local del jugador (código %d)." % error)


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
	var mission_progress: Dictionary = {}
	var actor := scene.get_node_or_null("Player")
	if actor != null and scene.has_method("make_campaign_level_progress_snapshot"):
		var snapshot: Dictionary = scene.call("make_campaign_level_progress_snapshot", actor)
		var missions: Variant = snapshot.get("missions", {})
		if missions is Dictionary:
			mission_progress = missions.duplicate(true)
	set_level(level_value, {
		"scene": scene.scene_file_path, "title": "Cementerio %d" % level_value,
		"map_bounds": {"min_x": -cell * 2.0, "max_x": float(grid.x) * cell, "min_z": -cell, "max_z": float(grid.y) * cell},
		"map_geometry": _map_geometry(scene),
		"mission_progress": mission_progress,
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
	if OS.get_name() == "Windows":
		var launcher := ProjectSettings.globalize_path("res://telemetry/start_dashboard.ps1")
		if FileAccess.file_exists(launcher):
			executable = "powershell.exe"
			arguments = PackedStringArray([
				"-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
				"-File", launcher, "-Port", str(dashboard_port),
				"-SpoolDir", _spool_directory(), "-ServerPath", server,
			])
	var pid := OS.create_process(executable, arguments)
	_web_started = pid > 0
	if pid <= 0:
		push_warning("El diario de partida está guardado. Para consultar SQLite ejecuta: python3 telemetry/server.py")


func _upload_pending_logs() -> void:
	if not enabled or _upload_in_flight:
		return
	var endpoint := _remote_endpoint()
	var publishable_key := _remote_key()
	if endpoint.is_empty() or publishable_key.is_empty():
		return
	if not endpoint.begins_with("https://"):
		push_warning("La URL de ingesta remota debe usar HTTPS. El diario local sigue guardándose.")
		return
	var spool_dir := _spool_directory()
	var files := DirAccess.get_files_at(spool_dir)
	files.sort()
	var events: Array[Dictionary] = []
	var offsets_after_success: Dictionary = {}
	for filename in files:
		if not filename.ends_with(".jsonl"):
			continue
		var full_path := spool_dir.path_join(filename)
		var file := FileAccess.open(full_path, FileAccess.READ)
		if file == null:
			continue
		var length := file.get_length()
		var offset := int(_upload_offsets.get(filename, 0))
		if length < offset:
			offset = 0
		file.seek(offset)
		var consumed_offset := offset
		while file.get_position() < length and events.size() < remote_batch_size:
			var line := file.get_line()
			var line_end := file.get_position()
			if line_end <= consumed_offset:
				break
			consumed_offset = line_end
			if line.strip_edges().is_empty():
				continue
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				events.append(parsed)
		file.close()
		if consumed_offset > offset:
			offsets_after_success[filename] = consumed_offset
		if events.size() >= remote_batch_size:
			break
	if events.is_empty():
		# Avanza sobre líneas vacías/corruptas para no bloquear la cola local.
		if not offsets_after_success.is_empty():
			_commit_upload_offsets(offsets_after_success)
		return
	_pending_upload_offsets = offsets_after_success
	var body := JSON.stringify({"events": events})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % publishable_key,
	])
	var error := _upload_request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_pending_upload_offsets.clear()
		push_warning("No se pudo iniciar la sincronización de telemetría (código %d). Se reintentará; el diario local está intacto." % error)
		return
	_upload_in_flight = true


func _on_upload_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_upload_in_flight = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		_commit_upload_offsets(_pending_upload_offsets)
	else:
		push_warning("La telemetría remota no respondió correctamente (HTTP %d). Se reintentará y el diario local permanece guardado." % response_code)
	_pending_upload_offsets.clear()


func _remote_endpoint() -> String:
	var environment_value := OS.get_environment("RESONANCE_SUPABASE_FUNCTION_URL")
	return environment_value if not environment_value.is_empty() else remote_ingest_url.strip_edges()


func _remote_key() -> String:
	var environment_value := OS.get_environment("RESONANCE_SUPABASE_PUBLISHABLE_KEY")
	return environment_value if not environment_value.is_empty() else remote_publishable_key.strip_edges()


func _upload_state_path() -> String:
	return _spool_directory().path_join("remote_upload_offsets.json")


func _load_upload_offsets() -> void:
	var path := _upload_state_path()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_upload_offsets = parsed


func _commit_upload_offsets(offsets: Dictionary) -> void:
	for filename in offsets:
		_upload_offsets[filename] = int(offsets[filename])
	var directory := _spool_directory()
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(_upload_state_path(), FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar el cursor de sincronización. Los eventos pueden volver a enviarse, pero el servidor elimina duplicados por event_id.")
		return
	file.store_string(JSON.stringify(_upload_offsets))
	file.close()


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

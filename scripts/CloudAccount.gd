extends Node
class_name CloudAccountManager

signal authentication_changed

## La app solo lleva la clave publicable; las cuentas y las partidas las maneja account-api.
@export var supabase_url: String = "https://nqcabupndnyvlhgvenwq.supabase.co"
@export var publishable_key: String = "sb_publishable_CsgNW6g4UMeblaOZbuUAew_ztRBQJAQ"
@export_range(5.0, 30.0, 1.0) var request_timeout: float = 12.0

var is_authenticated: bool = false
var account_id: String = ""
var username: String = ""

var _session_token: String = ""
var _session_expires_at: int = 0
var _http: HTTPRequest
var _pending_retry_timer: Timer
var _pending_saves: Dictionary = {}
var _request_busy: bool = false
var _queued_checkpoints: Dictionary = {}
var _checkpoint_writer_running: bool = false

const AUTH_SESSION_PATH: String = "user://cloud_account.cfg"
const PENDING_SAVES_PATH: String = "user://pending_cloud_saves.cfg"
const ACCOUNT_API_PATH: String = "/functions/v1/account-api"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = request_timeout
	add_child(_http)
	_pending_retry_timer = Timer.new()
	_pending_retry_timer.wait_time = 30.0
	_pending_retry_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pending_retry_timer.timeout.connect(_on_pending_retry_timeout)
	add_child(_pending_retry_timer)
	_pending_retry_timer.start()
	_load_auth_session()
	_load_pending_saves()
	if is_authenticated:
		call_deferred("_resume_saved_session")


func register_account(requested_username: String, password: String) -> Dictionary:
	var clean_username := requested_username.strip_edges().to_lower()
	if not _valid_username(clean_username):
		return {"ok": false, "error": "El ID debe tener 3–20 caracteres: letras, números o guion bajo."}
	if not _valid_password(password):
		return {"ok": false, "error": "La contraseña debe tener al menos 8 caracteres."}
	var response := await _request_json({
		"action": "register",
		"username": clean_username,
		"password": password,
	}, false)
	if not response.get("ok", false):
		return response
	var response_data: Variant = response.get("data", {})
	var session_data: Variant = response_data.get("session", {}) if response_data is Dictionary else {}
	if not _accept_session(session_data):
		return {"ok": false, "error": "El servidor no devolvió una sesión válida."}
	_save_auth_session()
	authentication_changed.emit()
	call_deferred("_flush_pending_saves")
	return {"ok": true, "username": username}


func login_account(requested_username: String, password: String) -> Dictionary:
	var clean_username := requested_username.strip_edges().to_lower()
	if not _valid_username(clean_username) or password.is_empty():
		return {"ok": false, "error": "Escribe tu ID y contraseña."}
	var response := await _request_json({
		"action": "login",
		"username": clean_username,
		"password": password,
	}, false)
	if not response.get("ok", false):
		return response
	var response_data: Variant = response.get("data", {})
	var session_data: Variant = response_data.get("session", {}) if response_data is Dictionary else {}
	if not _accept_session(session_data):
		return {"ok": false, "error": "El servidor no devolvió una sesión válida."}
	_save_auth_session()
	authentication_changed.emit()
	call_deferred("_flush_pending_saves")
	return {"ok": true, "username": username}


func sign_out() -> Dictionary:
	var server_response: Dictionary = {"ok": true}
	if _ensure_valid_session():
		server_response = await _request_json({"action": "logout"}, true)
	_clear_auth_session()
	authentication_changed.emit()
	return {"ok": true, "server_response": server_response.get("ok", false)}


func list_saves() -> Dictionary:
	if not _ensure_valid_session():
		return {"ok": false, "error": "Inicia sesión de nuevo para cargar tus partidas."}
	var response := await _request_json({"action": "list_saves"}, true)
	if not response.get("ok", false):
		return response
	var response_data: Variant = response.get("data", {})
	return {"ok": true, "data": response_data.get("saves", []) if response_data is Dictionary else []}


func get_save(slot: int) -> Dictionary:
	if slot < 1 or slot > 3:
		return {"ok": false, "error": "Espacio de guardado inválido."}
	if not _ensure_valid_session():
		return {"ok": false, "error": "Inicia sesión de nuevo para cargar tus partidas."}
	var response := await _request_json({"action": "load_save", "slot": slot}, true)
	if not response.get("ok", false):
		return response
	var response_data: Variant = response.get("data", {})
	if response_data is Dictionary and response_data.get("save") is Dictionary:
		return {"ok": true, "save": response_data["save"]}
	return {"ok": false, "error": "No se encontró esa partida."}


func create_or_replace_slot(slot: int, _save_name: String) -> Dictionary:
	if slot < 1 or slot > 3:
		return {"ok": false, "error": "Solo existen tres espacios de guardado."}
	if not _ensure_valid_session():
		return {"ok": false, "error": "Inicia sesión de nuevo para crear una partida."}
	return await _request_json({"action": "create_save", "slot": slot}, true)


func delete_slot(slot: int) -> Dictionary:
	if slot < 1 or slot > 3:
		return {"ok": false, "error": "Espacio de guardado inválido."}
	if not _ensure_valid_session():
		return {"ok": false, "error": "Inicia sesión de nuevo para borrar partidas."}
	return await _request_json({"action": "delete_save", "slot": slot}, true)


func save_checkpoint(next_level: int, snapshot: Dictionary, slot_override: int = -1) -> Dictionary:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return {"ok": false, "error": "No se encontró el progreso de la campaña."}
	var slot := slot_override if slot_override > 0 else int(game_manager.get("active_save_slot"))
	if slot < 1 or slot > 3 or account_id.is_empty():
		return {"ok": false, "error": "No hay una partida de cuenta seleccionada."}
	var safe_level := clampi(next_level, 1, 4)
	var clean_snapshot := snapshot.duplicate(true)
	clean_snapshot["level"] = safe_level
	clean_snapshot["campaign_completed"] = bool(clean_snapshot.get("campaign_completed", false))
	var save_payload := {
		"account_id": account_id,
		"slot": slot,
		"level": safe_level,
		"score": int(clean_snapshot.get("score", 0)),
		"save_data": clean_snapshot,
	}
	if _ensure_valid_session():
		var response := await _request_json({
			"action": "save_checkpoint",
			"slot": slot,
			"save_data": clean_snapshot,
		}, true)
		if response.get("ok", false):
			return {"ok": true, "pending": false}
	_queue_pending_save(slot, save_payload)
	return {"ok": true, "pending": true, "message": "Punto guardado en esta computadora; se sincronizará al reconectar."}


func queue_checkpoint(next_level: int, snapshot: Dictionary) -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return
	var slot := int(game_manager.get("active_save_slot"))
	if slot < 1 or slot > 3:
		return
	_queued_checkpoints[slot] = {
		"level": clampi(next_level, 1, 4),
		"snapshot": snapshot.duplicate(true),
	}
	if not _checkpoint_writer_running:
		call_deferred("_flush_queued_checkpoints")


func _flush_queued_checkpoints() -> void:
	if _checkpoint_writer_running:
		return
	_checkpoint_writer_running = true
	while not _queued_checkpoints.is_empty():
		var slot := int(_queued_checkpoints.keys()[0])
		var checkpoint: Dictionary = _queued_checkpoints[slot]
		_queued_checkpoints.erase(slot)
		var checkpoint_level := int(checkpoint.get("level", 1))
		var checkpoint_snapshot: Dictionary = checkpoint.get("snapshot", {})
		var response: Dictionary = await save_checkpoint(checkpoint_level, checkpoint_snapshot, slot)
		if not response.get("ok", false):
			push_warning(str(response.get("error", "No se pudo guardar el punto de control.")))
	_checkpoint_writer_running = false


func _request_json(payload: Dictionary, use_session: bool) -> Dictionary:
	if supabase_url.strip_edges().is_empty() or publishable_key.strip_edges().is_empty():
		return {"ok": false, "error": "Falta configurar la conexión con Supabase."}
	if use_session and not _ensure_valid_session():
		return {"ok": false, "error": "La sesión caducó. Inicia sesión otra vez."}
	while _request_busy:
		await get_tree().create_timer(0.05, true).timeout
	_request_busy = true
	var headers := PackedStringArray([
		"apikey: %s" % publishable_key.strip_edges(),
		"Content-Type: application/json",
		"Accept: application/json",
	])
	if use_session:
		headers.append("X-Game-Session: %s" % _session_token)
	var error := _http.request(
		supabase_url.trim_suffix("/") + ACCOUNT_API_PATH,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		_request_busy = false
		return {"ok": false, "error": "No se pudo iniciar la conexión (código %d)." % error}
	var result: Array = await _http.request_completed
	_request_busy = false
	var response_code := int(result[1])
	var response_body: PackedByteArray = result[3]
	var body_text := response_body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text) if not body_text.is_empty() else {}
	if parsed == null:
		parsed = {}
	var ok := int(result[0]) == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if ok:
		return {"ok": true, "data": parsed, "status": response_code}
	var message := "El servidor respondió con error HTTP %d." % response_code
	if parsed is Dictionary:
		message = str(parsed.get("error", parsed.get("message", message)))
	if use_session and response_code == 401:
		is_authenticated = false
		_session_expires_at = 0
		_save_auth_session()
		authentication_changed.emit()
	return {"ok": false, "error": message, "status": response_code}


func _valid_username(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{3,20}$")
	return pattern.search(value) != null


func _valid_password(value: String) -> bool:
	var password_bytes := value.to_utf8_buffer().size()
	return password_bytes >= 8 and password_bytes <= 72


func _ensure_valid_session() -> bool:
	return is_authenticated and not account_id.is_empty() and not _session_token.is_empty() and _session_expires_at > int(Time.get_unix_time_from_system()) + 60


func _accept_session(session_data: Variant) -> bool:
	if not session_data is Dictionary:
		return false
	var new_id := str(session_data.get("account_id", ""))
	var new_username := str(session_data.get("username", ""))
	var new_token := str(session_data.get("session_token", ""))
	var new_expiry := int(session_data.get("expires_at", 0))
	if new_id.is_empty() or new_username.is_empty() or new_token.length() != 64 or new_expiry <= int(Time.get_unix_time_from_system()):
		return false
	account_id = new_id
	username = new_username
	_session_token = new_token
	_session_expires_at = new_expiry
	is_authenticated = true
	return true


func _load_auth_session() -> void:
	var config := ConfigFile.new()
	if config.load(AUTH_SESSION_PATH) != OK:
		return
	account_id = str(config.get_value("account", "account_id", ""))
	username = str(config.get_value("account", "username", ""))
	_session_token = str(config.get_value("account", "session_token", ""))
	_session_expires_at = int(config.get_value("account", "expires_at", 0))
	is_authenticated = not account_id.is_empty() and not _session_token.is_empty()
	is_authenticated = _ensure_valid_session()
	if not is_authenticated:
		_clear_auth_session()


func _save_auth_session() -> void:
	var config := ConfigFile.new()
	config.set_value("account", "account_id", account_id)
	config.set_value("account", "username", username)
	config.set_value("account", "session_token", _session_token)
	config.set_value("account", "expires_at", _session_expires_at)
	var error := config.save(AUTH_SESSION_PATH)
	if error != OK:
		push_warning("No se pudo guardar la sesión localmente (código %d)." % error)


func _clear_auth_session() -> void:
	account_id = ""
	username = ""
	_session_token = ""
	_session_expires_at = 0
	is_authenticated = false
	var absolute_path := ProjectSettings.globalize_path(AUTH_SESSION_PATH)
	if FileAccess.file_exists(AUTH_SESSION_PATH):
		DirAccess.remove_absolute(absolute_path)


func _resume_saved_session() -> void:
	authentication_changed.emit()
	if is_authenticated:
		await _flush_pending_saves()


func _queue_pending_save(slot: int, save_payload: Dictionary) -> void:
	var pending_key := "%s:%d" % [account_id, slot]
	_pending_saves[pending_key] = {"account_id": account_id, "payload": save_payload}
	var config := ConfigFile.new()
	config.set_value("pending", "records", _pending_saves)
	var error := config.save(PENDING_SAVES_PATH)
	if error != OK:
		push_warning("No se pudo guardar localmente el punto pendiente (código %d)." % error)


func _load_pending_saves() -> void:
	var config := ConfigFile.new()
	if config.load(PENDING_SAVES_PATH) != OK:
		return
	var records: Variant = config.get_value("pending", "records", {})
	if records is Dictionary:
		_pending_saves = records


func _on_pending_retry_timeout() -> void:
	if is_authenticated and not _pending_saves.is_empty():
		call_deferred("_flush_pending_saves")


func _flush_pending_saves() -> void:
	if not _ensure_valid_session():
		return
	for pending_key in _pending_saves.keys():
		var pending: Variant = _pending_saves[pending_key]
		if not pending is Dictionary or str(pending.get("account_id", "")) != account_id:
			continue
		var payload: Variant = pending.get("payload", {})
		if not payload is Dictionary:
			_pending_saves.erase(pending_key)
			continue
		var api_payload := {
			"action": "save_checkpoint",
			"slot": int(payload.get("slot", 0)),
			"save_data": payload.get("save_data", {}),
		}
		var response := await _request_json(api_payload, true)
		if response.get("ok", false):
			_pending_saves.erase(pending_key)
	var config := ConfigFile.new()
	config.set_value("pending", "records", _pending_saves)
	config.save(PENDING_SAVES_PATH)

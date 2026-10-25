extends CanvasLayer

const SAVE_SLOT_COUNT: int = 3

var _account: CloudAccountManager
var _panel: PanelContainer
var _username_input: LineEdit
var _password_input: LineEdit
var _login_box: VBoxContainer
var _signed_in_box: HBoxContainer
var _slots_box: VBoxContainer
var _status_label: Label
var _register_button: Button
var _login_button: Button
var _sign_out_button: Button
var _refresh_button: Button
var _confirm_dialog: ConfirmationDialog
var _pending_replace_slot: int = 0
var _pending_confirmation_action: String = ""
var _slots_loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_account = get_node("/root/CloudAccount") as CloudAccountManager
	_build_interface()
	_account.authentication_changed.connect(_on_authentication_changed)
	_render_authentication_state()


func _build_interface() -> void:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.01, 0.025, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -390.0
	_panel.offset_top = -310.0
	_panel.offset_right = 390.0
	_panel.offset_bottom = 310.0
	_panel.add_theme_stylebox_override("panel", _panel_style())
	screen.add_child(_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)

	var heading := HBoxContainer.new()
	var title := Label.new()
	title.text = "PARTIDAS GUARDADAS"
	title.add_theme_color_override("font_color", Color("#e8c98e"))
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button := _make_button("CERRAR", 100)
	close_button.pressed.connect(queue_free)
	heading.add_child(close_button)
	content.add_child(heading)
	content.add_child(_make_separator())

	_login_box = VBoxContainer.new()
	_login_box.add_theme_constant_override("separation", 8)
	var login_hint := Label.new()
	login_hint.text = "Crea un ID único y una contraseña para guardar hasta 3 partidas en la nube. Guarda tu contraseña: no hay recuperación automática."
	login_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	login_hint.add_theme_color_override("font_color", Color("#c2b9c7"))
	_login_box.add_child(login_hint)

	_username_input = LineEdit.new()
	_username_input.placeholder_text = "ID único (3–20 letras, números o guion bajo)"
	_username_input.max_length = 20
	_login_box.add_child(_username_input)

	_password_input = LineEdit.new()
	_password_input.placeholder_text = "Contraseña (mínimo 8 caracteres)"
	_password_input.secret = true
	_password_input.max_length = 72
	_login_box.add_child(_password_input)

	var auth_buttons := HBoxContainer.new()
	auth_buttons.add_theme_constant_override("separation", 8)
	_register_button = _make_button("CREAR ID", 150)
	_register_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_register_button.pressed.connect(_on_register_pressed)
	auth_buttons.add_child(_register_button)
	_login_button = _make_button("INICIAR SESIÓN", 180)
	_login_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_login_button.pressed.connect(_on_login_pressed)
	auth_buttons.add_child(_login_button)
	_login_box.add_child(auth_buttons)
	content.add_child(_login_box)

	_signed_in_box = HBoxContainer.new()
	_signed_in_box.visible = false
	var account_label := Label.new()
	account_label.name = "AccountLabel"
	account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_label.add_theme_color_override("font_color", Color("#9ee3c4"))
	_signed_in_box.add_child(account_label)
	_refresh_button = _make_button("ACTUALIZAR", 120)
	_refresh_button.pressed.connect(_load_slots)
	_signed_in_box.add_child(_refresh_button)
	_sign_out_button = _make_button("CERRAR SESIÓN", 150)
	_sign_out_button.pressed.connect(_on_sign_out_pressed)
	_signed_in_box.add_child(_sign_out_button)
	content.add_child(_signed_in_box)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 24)
	_status_label.add_theme_color_override("font_color", Color("#d8c7a4"))
	content.add_child(_status_label)

	var slots_title := Label.new()
	slots_title.text = "TUS ESPACIOS · MÁXIMO 3"
	slots_title.add_theme_color_override("font_color", Color("#e8c98e"))
	slots_title.add_theme_font_size_override("font_size", 15)
	content.add_child(slots_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 235)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_slots_box)

	var guest_note := Label.new()
	guest_note.text = "Puedes cerrar esta ventana y jugar como invitado. El invitado inicia una partida nueva sin cuenta."
	guest_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guest_note.add_theme_color_override("font_color", Color("#8fa59c"))
	content.add_child(guest_note)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Reemplazar partida"
	_confirm_dialog.dialog_text = "Este espacio ya tiene una partida. ¿Quieres reemplazarla con una nueva?"
	_confirm_dialog.confirmed.connect(_on_confirmation_confirmed)
	add_child(_confirm_dialog)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.025, 0.055, 0.98)
	style.border_color = Color(0.55, 0.28, 0.2, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24.0)
	return style


func _make_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color(0.36, 0.25, 0.27))
	return separator


func _make_button(text: String, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 42)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("#f4e5ce"))
	button.add_theme_stylebox_override("normal", _button_style(Color("#38221f"), Color("#bd7139")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#512c24"), Color("#f0a95f")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#241922"), Color("#bd7139")))
	return button


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8.0)
	return style


func _render_authentication_state() -> void:
	var signed_in := _account.is_authenticated
	_login_box.visible = not signed_in
	_signed_in_box.visible = signed_in
	if signed_in:
		_signed_in_box.get_node("AccountLabel").text = "Conectado como %s" % _account.username
		_status_label.text = "Tus partidas están ligadas a este ID."
		_load_slots()
	else:
		_clear_slots("Crea un ID o inicia sesión para ver tus tres espacios de guardado.")


func _on_authentication_changed() -> void:
	_render_authentication_state()


func _on_register_pressed() -> void:
	_register_button.disabled = true
	_login_button.disabled = true
	_set_status("Creando tu ID…", false)
	var response: Dictionary = await _account.register_account(_username_input.text, _password_input.text)
	_register_button.disabled = false
	_login_button.disabled = false
	if response.get("ok", false):
		_password_input.clear()
		_set_status("Cuenta creada. Ya puedes guardar tus partidas.", false)
		_render_authentication_state()
	else:
		_set_status(str(response.get("error", "No se pudo crear el ID.")), true)


func _on_login_pressed() -> void:
	_register_button.disabled = true
	_login_button.disabled = true
	_set_status("Iniciando sesión…", false)
	var response: Dictionary = await _account.login_account(_username_input.text, _password_input.text)
	_register_button.disabled = false
	_login_button.disabled = false
	if response.get("ok", false):
		_password_input.clear()
		_set_status("Sesión iniciada.", false)
		_render_authentication_state()
	else:
		_set_status(str(response.get("error", "No se pudo iniciar sesión.")), true)


func _on_sign_out_pressed() -> void:
	_sign_out_button.disabled = true
	await _account.sign_out()
	_sign_out_button.disabled = false
	_render_authentication_state()
	_set_status("Sesión cerrada.", false)


func _load_slots() -> void:
	if _slots_loading or not _account.is_authenticated:
		return
	_slots_loading = true
	_refresh_button.disabled = true
	var response: Dictionary = await _account.list_saves()
	_refresh_button.disabled = false
	_slots_loading = false
	if not response.get("ok", false):
		_set_status(str(response.get("error", "No se pudieron cargar los espacios.")), true)
		return
	var raw_records: Variant = response.get("data", [])
	if not raw_records is Array:
		_set_status("Respuesta inesperada al cargar las partidas.", true)
		return
	var records: Array = raw_records
	_populate_slots(records)
	_set_status("Partidas sincronizadas con la nube.", false)


func _clear_slots(message: String) -> void:
	for child in _slots_box.get_children():
		child.queue_free()
	var hint := Label.new()
	hint.text = message
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("#a99dad"))
	_slots_box.add_child(hint)


func _populate_slots(records: Array) -> void:
	for child in _slots_box.get_children():
		child.queue_free()
	for slot in range(1, SAVE_SLOT_COUNT + 1):
		var save_record: Dictionary = {}
		for record in records:
			if record is Dictionary and int(record.get("slot", 0)) == slot:
				save_record = record
				break
		_slots_box.add_child(_make_slot_row(slot, save_record))


func _make_slot_row(slot: int, save_record: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.065, 0.09, 0.85)
	style.border_color = Color(0.25, 0.22, 0.24, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "ESPACIO %d" % slot
	title.add_theme_color_override("font_color", Color("#e8c98e"))
	title.add_theme_font_size_override("font_size", 15)
	info.add_child(title)

	var details := Label.new()
	var occupied := not save_record.is_empty()
	var completed := false
	if occupied:
		var data: Variant = save_record.get("save_data", {})
		completed = data is Dictionary and bool(data.get("campaign_completed", false))
		if completed:
			details.text = "Campaña completada · Puntuación %d" % int(save_record.get("score", 0))
		else:
			details.text = "Nivel %d · Puntuación %d · %s" % [
				int(save_record.get("level", 1)),
				int(save_record.get("score", 0)),
				str(save_record.get("updated_at", "")),
			]
	else:
		details.text = "Vacío · empieza una campaña nueva"
	details.add_theme_color_override("font_color", Color("#b8b2bc"))
	details.add_theme_font_size_override("font_size", 11)
	info.add_child(details)
	row.add_child(info)

	var continue_button := _make_button("CONTINUAR" if not completed else "COMPLETADA", 118)
	continue_button.disabled = not occupied or completed
	continue_button.pressed.connect(_on_continue_slot_pressed.bind(slot))
	row.add_child(continue_button)
	var new_button := _make_button("REEMPLAZAR" if occupied else "NUEVA", 112)
	new_button.pressed.connect(_on_new_slot_pressed.bind(slot, occupied))
	row.add_child(new_button)
	if occupied:
		var delete_button := _make_button("BORRAR", 82)
		delete_button.pressed.connect(_on_delete_slot_pressed.bind(slot))
		row.add_child(delete_button)
	return panel


func _on_new_slot_pressed(slot: int, occupied: bool) -> void:
	if occupied:
		_pending_replace_slot = slot
		_pending_confirmation_action = "replace"
		_confirm_dialog.title = "Reemplazar partida"
		_confirm_dialog.dialog_text = "El espacio %d ya tiene una partida. ¿Quieres reemplazarla?" % slot
		_confirm_dialog.popup_centered()
	else:
		_create_new_slot(slot)


func _on_confirmation_confirmed() -> void:
	if _pending_confirmation_action == "delete":
		_delete_confirmed_slot()
	elif _pending_confirmation_action == "replace" and _pending_replace_slot > 0:
		_create_new_slot(_pending_replace_slot)
	_pending_confirmation_action = ""
	_pending_replace_slot = 0


func _create_new_slot(slot: int) -> void:
	_set_status("Creando espacio %d…" % slot, false)
	var response: Dictionary = await _account.create_or_replace_slot(slot, "Partida %d" % slot)
	if not response.get("ok", false):
		_set_status(str(response.get("error", "No se pudo crear la partida.")), true)
		return
	var game_manager := get_node("/root/GameManager")
	game_manager.call("start_new_campaign", slot, false)
	_start_gameplay_session("new_saved_game", {"slot": slot})
	_change_to_level(1)


func _on_continue_slot_pressed(slot: int) -> void:
	_set_status("Cargando espacio %d…" % slot, false)
	var response: Dictionary = await _account.get_save(slot)
	if not response.get("ok", false):
		_set_status(str(response.get("error", "No se pudo cargar la partida.")), true)
		return
	var save_data: Variant = response.get("save", {})
	if not save_data is Dictionary:
		_set_status("El archivo de guardado no tiene el formato esperado.", true)
		return
	var data: Variant = save_data.get("save_data", {})
	if not data is Dictionary or bool(data.get("campaign_completed", false)):
		_set_status("Esta campaña ya está completada. Crea una nueva para volver a jugar.", true)
		return
	var game_manager := get_node("/root/GameManager")
	game_manager.call("restore_campaign", save_data, slot)
	var level := clampi(int(save_data.get("level", 1)), 1, 4)
	_start_gameplay_session("saved_game_loaded", {"slot": slot, "level": level})
	_change_to_level(level)


func _on_delete_slot_pressed(slot: int) -> void:
	_pending_replace_slot = slot
	_pending_confirmation_action = "delete"
	_confirm_dialog.title = "Borrar partida"
	_confirm_dialog.dialog_text = "¿Borrar el espacio %d? Esta acción no se puede deshacer." % slot
	_confirm_dialog.popup_centered()


func _delete_confirmed_slot() -> void:
	var slot := _pending_replace_slot
	_confirm_dialog.title = "Reemplazar partida"
	if slot < 1 or slot > SAVE_SLOT_COUNT:
		return
	var response: Dictionary = await _account.delete_slot(slot)
	if response.get("ok", false):
		_set_status("Espacio %d borrado." % slot, false)
		_load_slots()
	else:
		_set_status(str(response.get("error", "No se pudo borrar el espacio.")), true)


func _start_gameplay_session(event_kind: String, data: Dictionary) -> void:
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.call("start_session", _account.username if _account.is_authenticated else "Invitado")
		logger.call("record", event_kind, data)


func _change_to_level(level: int) -> void:
	get_tree().paused = false
	var scene_path := "res://scenes/Level_%02d.tscn" % clampi(level, 1, 4)
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_set_status("No se pudo abrir el nivel %d (error %d)." % [level, error], true)
		return
	queue_free()


func _set_status(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", Color("#ff8d85") if is_error else Color("#d8c7a4"))

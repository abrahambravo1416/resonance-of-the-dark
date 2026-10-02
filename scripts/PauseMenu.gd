extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"

var _overlay: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_pause_action()
	_build_interface()
	_overlay.visible = false


func _input(event: InputEvent) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and bool(player.get("is_dead")):
		return
	if player != null and bool(player.get_meta("level_2_intro_active", false)):
		return
	if not event.is_echo() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game")):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if get_tree().paused:
		_resume_game()
	else:
		get_tree().paused = true
		_overlay.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_interface() -> void:
	_overlay = Control.new()
	_overlay.name = "PauseOverlay"
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0.035, 0.025, 0.055, 0.86)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.add_child(dimmer)

	var layout := VBoxContainer.new()
	layout.name = "PauseLayout"
	layout.set_anchors_preset(Control.PRESET_CENTER)
	layout.anchor_left = 0.5
	layout.anchor_top = 0.5
	layout.anchor_right = 0.5
	layout.anchor_bottom = 0.5
	layout.offset_left = -200.0
	layout.offset_top = -190.0
	layout.offset_right = 200.0
	layout.offset_bottom = 190.0
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 20)
	layout.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.add_child(layout)

	var title := Label.new()
	title.text = "JUEGO EN PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("f2d5a0"))
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12.0
	layout.add_child(spacer)

	var resume_button := _make_button("REANUDAR")
	resume_button.pressed.connect(_resume_game)
	layout.add_child(resume_button)

	var menu_button := _make_button("MENÚ PRINCIPAL")
	menu_button.pressed.connect(_go_to_main_menu)
	layout.add_child(menu_button)

	var exit_button := _make_button("SALIR")
	exit_button.pressed.connect(_quit_game)
	layout.add_child(exit_button)


func _make_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(300.0, 52.0)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("fff0d4"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("30233b")
	normal.border_color = Color("a65e38")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("523044")
	hover.border_color = Color("f0a34c")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _resume_game() -> void:
	_overlay.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _go_to_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _quit_game() -> void:
	get_tree().quit()


func _ensure_pause_action() -> void:
	if not InputMap.has_action("pause_game"):
		InputMap.add_action("pause_game")
	var pause_key := InputEventKey.new()
	pause_key.physical_keycode = KEY_P
	for existing_event in InputMap.action_get_events("pause_game"):
		if existing_event is InputEventKey and existing_event.physical_keycode == KEY_P:
			return
	InputMap.action_add_event("pause_game", pause_key)

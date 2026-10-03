extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const SFX_MENU_CLICK: AudioStreamWAV = preload("res://audio/Efectos cortos/click_menu.wav")

var _overlay: Control
var _subtitle: Label
var _player: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	_overlay.visible = false
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("player_died"):
		var callback := Callable(self, "_show_game_over")
		if not _player.is_connected("player_died", callback):
			_player.connect("player_died", callback)
		if bool(_player.get("is_dead")):
			_show_game_over()
	if LevelManager != null and not LevelManager.level_time_expired.is_connected(_show_timeout_game_over):
		LevelManager.level_time_expired.connect(_show_timeout_game_over)


func _build_interface() -> void:
	_overlay = Control.new()
	_overlay.name = "GameOverOverlay"
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dimmer := ColorRect.new()
	dimmer.name = "BloodDimmer"
	dimmer.color = Color(0.09, 0.015, 0.025, 0.9)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.add_child(dimmer)

	var layout := VBoxContainer.new()
	layout.name = "GameOverLayout"
	layout.set_anchors_preset(Control.PRESET_CENTER)
	layout.anchor_left = 0.5
	layout.anchor_top = 0.5
	layout.anchor_right = 0.5
	layout.anchor_bottom = 0.5
	layout.offset_left = -220.0
	layout.offset_top = -210.0
	layout.offset_right = 220.0
	layout.offset_bottom = 210.0
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 18)
	layout.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.add_child(layout)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("ef6a62"))
	title.add_theme_font_size_override("font_size", 48)
	layout.add_child(title)

	_subtitle = Label.new()
	_subtitle.text = "No fuiste tan hábil"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", Color("e6c7c3"))
	_subtitle.add_theme_font_size_override("font_size", 18)
	layout.add_child(_subtitle)

	var penalty_line := Label.new()
	penalty_line.name = "ScorePenalty"
	penalty_line.text = "- 50 en puntuación final"
	penalty_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	penalty_line.add_theme_color_override("font_color", Color("e6c7c3"))
	penalty_line.add_theme_font_size_override("font_size", 16)
	layout.add_child(penalty_line)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12.0
	layout.add_child(spacer)

	var restart_button := _make_button("REINICIAR NIVEL")
	restart_button.pressed.connect(_restart_level)
	layout.add_child(restart_button)

	var menu_button := _make_button("MENÚ PRINCIPAL")
	menu_button.pressed.connect(_go_to_main_menu)
	layout.add_child(menu_button)

	var exit_button := _make_button("SALIR")
	exit_button.pressed.connect(_quit_game)
	layout.add_child(exit_button)


func _make_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(_play_menu_click)
	button.custom_minimum_size = Vector2(320.0, 52.0)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("fff0d4"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("351a25")
	normal.border_color = Color("a94b47")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("54232d")
	hover.border_color = Color("f07968")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _play_menu_click() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = SFX_MENU_CLICK
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _show_game_over() -> void:
	_overlay.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_timeout_game_over() -> void:
	_subtitle.text = "¡Se acabó el tiempo!"
	_show_game_over()


func _restart_level() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _go_to_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _quit_game() -> void:
	get_tree().quit()

extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const SFX_MENU_CLICK: AudioStreamWAV = preload("res://audio/Efectos cortos/click_menu.wav")

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
	_overlay = $PauseOverlay
	$PauseOverlay/PauseLayout/ResumeButton.pressed.connect(_play_menu_click)
	$PauseOverlay/PauseLayout/ResumeButton.pressed.connect(_resume_game)
	$PauseOverlay/PauseLayout/MenuButton.pressed.connect(_play_menu_click)
	$PauseOverlay/PauseLayout/MenuButton.pressed.connect(_go_to_main_menu)
	$PauseOverlay/PauseLayout/ControlsButton.pressed.connect(_play_menu_click)
	$PauseOverlay/PauseLayout/ControlsButton.pressed.connect(_open_control_settings)
	$PauseOverlay/PauseLayout/ExitButton.pressed.connect(_play_menu_click)
	$PauseOverlay/PauseLayout/ExitButton.pressed.connect(_quit_game)


func _play_menu_click() -> void:
	var player := preload("res://scenes/ui/SoundEffect.tscn").instantiate() as AudioStreamPlayer
	player.stream = SFX_MENU_CLICK
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _resume_game() -> void:
	_overlay.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _go_to_main_menu() -> void:
	_end_session("returned_to_menu")
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _quit_game() -> void:
	_end_session("quit")
	get_tree().quit()


func _open_control_settings() -> void:
	var touch_hud := get_node_or_null("/root/TouchHUD")
	if touch_hud != null:
		touch_hud.call("open_settings")


func _ensure_pause_action() -> void:
	if not InputMap.has_action("pause_game"):
		InputMap.add_action("pause_game")
	var pause_key := InputEventKey.new()
	pause_key.physical_keycode = KEY_P
	for existing_event in InputMap.action_get_events("pause_game"):
		if existing_event is InputEventKey and existing_event.physical_keycode == KEY_P:
			return
	InputMap.action_add_event("pause_game", pause_key)

func _end_session(outcome: String) -> void:
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.call("end_session", outcome)

extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const SFX_MENU_CLICK: AudioStreamWAV = preload("res://audio/Efectos cortos/click_menu.wav")

var _overlay: Control
var _subtitle: Label
var _player: Node
var _checkpoint_queued: bool = false


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
	var manager := get_node_or_null("/root/LevelManager")
	if manager != null and not manager.level_time_expired.is_connected(_show_timeout_game_over):
		manager.level_time_expired.connect(_show_timeout_game_over)


func _build_interface() -> void:
	_overlay = $GameOverOverlay
	_subtitle = $GameOverOverlay/GameOverLayout/Subtitle
	$GameOverOverlay/GameOverLayout/RestartButton.pressed.connect(_play_menu_click)
	$GameOverOverlay/GameOverLayout/RestartButton.pressed.connect(_restart_level)
	$GameOverOverlay/GameOverLayout/MenuButton.pressed.connect(_play_menu_click)
	$GameOverOverlay/GameOverLayout/MenuButton.pressed.connect(_go_to_main_menu)
	$GameOverOverlay/GameOverLayout/ExitButton.pressed.connect(_play_menu_click)
	$GameOverOverlay/GameOverLayout/ExitButton.pressed.connect(_quit_game)


func _play_menu_click() -> void:
	var player := preload("res://scenes/ui/SoundEffect.tscn").instantiate() as AudioStreamPlayer
	player.stream = SFX_MENU_CLICK
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _show_game_over() -> void:
	_overlay.visible = true
	_queue_campaign_checkpoint()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _queue_campaign_checkpoint() -> void:
	if _checkpoint_queued:
		return
	var game_manager := get_node_or_null("/root/GameManager")
	var account := get_node_or_null("/root/CloudAccount")
	if game_manager == null or account == null or int(game_manager.get("active_save_slot")) < 1:
		return
	var level := 1
	if _player != null and is_instance_valid(_player):
		level = clampi(int(_player.get("current_level_number")), 1, 4)
	var snapshot: Dictionary = game_manager.call("make_campaign_snapshot", level, false)
	account.call("queue_checkpoint", level, snapshot)
	_checkpoint_queued = true


func _show_timeout_game_over() -> void:
	_subtitle.text = "¡Se acabó el tiempo!"
	_show_game_over()


func _restart_level() -> void:
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.call("record", "level_restarted", {"reason": "game_over"})
	get_tree().paused = false
	get_tree().reload_current_scene()


func _go_to_main_menu() -> void:
	_end_session("returned_to_menu")
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _quit_game() -> void:
	_end_session("quit")
	get_tree().quit()

func _end_session(outcome: String) -> void:
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.call("end_session", outcome)

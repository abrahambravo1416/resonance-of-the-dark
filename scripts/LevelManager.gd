extends Node

signal level_completed(completed_level: int, next_level: int)
signal restart_started
signal level_time_expired

const LEVEL_SCENE_PATHS: Array[String] = [
	"res://scenes/Level_01.tscn",
	"res://scenes/Level_02.tscn",
	"res://scenes/Level_03.tscn",
]
const LEVEL_DURATION_SECONDS: int = 300

@export var restart_delay: float = 1.0

var current_level_index: int = 0
var seconds_left: int = LEVEL_DURATION_SECONDS
var _player: Node
var _restart_pending: bool = false
var _timer_running: bool = false
var _timer_fraction: float = 0.0
var _timer_hud_layer: CanvasLayer
var _timer_label: Label


func _ready() -> void:
	_sync_level_index_with_scene()
	_create_timer_hud()
	set_gameplay_hud_visible(false)


func _process(delta: float) -> void:
	if not _timer_running or get_tree().paused:
		return
	_timer_fraction += delta
	if _timer_fraction >= 1.0:
		var elapsed_seconds := int(_timer_fraction)
		_timer_fraction -= elapsed_seconds
		seconds_left = maxi(0, seconds_left - elapsed_seconds)
		_update_timer_hud()
		if seconds_left == 0:
			_expire_level_timer()


func register_player(player: Node) -> void:
	_player = player
	_sync_level_index_with_scene()
	seconds_left = LEVEL_DURATION_SECONDS
	_timer_fraction = 0.0
	_timer_running = true
	set_gameplay_hud_visible(true)
	_update_timer_hud()


func stop_level_timer() -> void:
	_timer_running = false


func refresh_time_score_hud() -> void:
	_update_timer_hud()


func set_gameplay_hud_visible(visible: bool) -> void:
	if _timer_hud_layer != null:
		_timer_hud_layer.visible = visible


func check_level_completion() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	return _player.has_method("can_escape_cemetery") and bool(_player.call("can_escape_cemetery"))


func restart_current_level() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	restart_started.emit()
	await get_tree().create_timer(restart_delay).timeout
	get_tree().reload_current_scene()
	_restart_pending = false


func _expire_level_timer() -> void:
	if not _timer_running:
		return
	_timer_running = false
	get_node("/root/GameManager").apply_penalty()
	_update_timer_hud()
	if _player != null and is_instance_valid(_player) and _player.has_method("freeze_controls"):
		_player.call("freeze_controls")
	level_time_expired.emit()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _create_timer_hud() -> void:
	_timer_hud_layer = CanvasLayer.new()
	_timer_hud_layer.name = "TimeScoreHUD"
	_timer_hud_layer.layer = 8
	add_child(_timer_hud_layer)
	var container := VBoxContainer.new()
	container.name = "TimeScore"
	container.position = Vector2(28.0, 102.0)
	container.add_theme_constant_override("separation", 4)
	_timer_hud_layer.add_child(container)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 18)
	_timer_label.add_theme_color_override("font_color", Color("f2d5a0"))
	container.add_child(_timer_label)
	var score_label := Label.new()
	score_label.name = "Score"
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color("e2c7a5"))
	container.add_child(score_label)
	_update_timer_hud()


func _update_timer_hud() -> void:
	if _timer_label != null:
		_timer_label.text = "TIEMPO  %02d:%02d" % [floori(float(seconds_left) / 60.0), seconds_left % 60]
	var score_label := get_node_or_null("TimeScoreHUD/TimeScore/Score") as Label
	if score_label != null:
		score_label.text = "PUNTUACIÓN  %d" % get_node("/root/GameManager").total_score


func _sync_level_index_with_scene() -> void:
	var scene_path := get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
	var scene_name := scene_path.get_file().get_basename()
	for i in LEVEL_SCENE_PATHS.size():
		if scene_name == LEVEL_SCENE_PATHS[i].get_file().get_basename():
			current_level_index = i
			return

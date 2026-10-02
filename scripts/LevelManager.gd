extends Node

signal level_completed(completed_level: int, next_level: int)
signal restart_started

const LEVEL_SCENE_PATHS: Array[String] = [
	"res://scenes/Level_01.tscn",
	"res://scenes/Level_02.tscn",
]

@export var restart_delay: float = 1.0

var current_level_index: int = 0
var _player: Node
var _restart_pending: bool = false


func _ready() -> void:
	_sync_level_index_with_scene()


func register_player(player: Node) -> void:
	_player = player
	_sync_level_index_with_scene()


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


func _sync_level_index_with_scene() -> void:
	var scene_path := get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
	var scene_name := scene_path.get_file().get_basename()
	for i in LEVEL_SCENE_PATHS.size():
		if scene_name == LEVEL_SCENE_PATHS[i].get_file().get_basename():
			current_level_index = i
			return

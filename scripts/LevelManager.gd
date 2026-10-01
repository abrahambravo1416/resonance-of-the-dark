extends Node

signal level_completed(completed_level: int, next_level: int)
signal restart_started

const LEVEL_SCENE_PATHS: Array[String] = [
	"res://scenes/Level_01.tscn",
	"res://scenes/Level_02.tscn",
	"res://scenes/Level_03.tscn",
	"res://scenes/Level_04.tscn",
]

@export var restart_delay: float = 1.0

var current_level_index: int = 0
var _player: Node
var _restart_pending: bool = false
var _completion_pending: bool = false


func _ready() -> void:
	_sync_level_index_with_scene()


func register_player(player: Node) -> void:
	_player = player
	_sync_level_index_with_scene()


func check_level_completion() -> bool:
	if _completion_pending or _player == null or not is_instance_valid(_player):
		return false
	var collected := int(_player.get("items_collected"))
	var required := int(_player.get("total_items_needed"))
	if collected < required:
		return false
	_completion_pending = true
	var completed_level := current_level_index + 1
	if current_level_index + 1 < LEVEL_SCENE_PATHS.size():
		var next_index := current_level_index + 1
		level_completed.emit(completed_level, next_index + 1)
		current_level_index = next_index
		var error := get_tree().change_scene_to_file(LEVEL_SCENE_PATHS[next_index])
		if error != OK:
			current_level_index = next_index - 1
			_completion_pending = false
			push_error("No se pudo cargar el siguiente nivel: %s (error %d)." % [LEVEL_SCENE_PATHS[next_index], error])
			return false
	else:
		level_completed.emit(completed_level, 0)
		print("Ritual completado: terminaste los cuatro niveles.")
	return true


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

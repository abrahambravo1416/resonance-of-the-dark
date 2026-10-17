extends Node3D
## Encuentros opcionales: no modifican misiones, tiempos, vida o enemigos.

@export_enum("npc", "memory") var encounter_type: String = "npc"
@export var encounter_id: String = "keeper"
@export var display_name: String = "El custodio"
@export_multiline var lines: Array[String] = ["No todas las voces de este cementerio quieren hacerte daño."]
@export_range(0.5, 6.0, 0.1) var interaction_distance: float = 2.7
@export var repeat_dialogue: bool = true
@export var visual: Node3D
@export var marker: Label3D

var collected: bool = false
var _line_index: int = 0
var _base_y: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	add_to_group("narrative_points")
	if visual != null:
		_base_y = visual.position.y
	if marker != null:
		marker.text = display_name
		marker.visible = false


func _process(delta: float) -> void:
	_time += delta
	if visual != null and encounter_type == "memory" and not collected:
		visual.position.y = _base_y + sin(_time * 1.7) * 0.055


func interact_narrative(player: Node3D) -> String:
	if collected or lines.is_empty():
		return ""
	var line := lines[mini(_line_index, lines.size() - 1)]
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.record("memory_collected" if encounter_type == "memory" else "npc_dialogue", {"id": encounter_id, "name": display_name, "line": line, "line_index": _line_index}, player.global_position)
	if encounter_type == "memory":
		collected = true
		visible = false
	elif repeat_dialogue:
		_line_index = (_line_index + 1) % lines.size()
	else:
		_line_index = mini(_line_index + 1, lines.size() - 1)
	return line

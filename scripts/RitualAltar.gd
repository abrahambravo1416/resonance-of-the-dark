extends Node3D
class_name RitualAltar

signal ritual_activated(altar: RitualAltar, world_position: Vector3)

@export var is_lit: bool = false

var altar_light: OmniLight3D
var proximity_area: Area3D
var _nearby_players: Array[Node3D] = []


func _ready() -> void:
	add_to_group("ritual_altars")
	proximity_area = get_node_or_null("ProximityArea") as Area3D
	if proximity_area != null:
		proximity_area.monitoring = true
		proximity_area.monitorable = true
		proximity_area.collision_layer = 0
		proximity_area.collision_mask = 1
		proximity_area.body_entered.connect(_on_body_entered)
		proximity_area.body_exited.connect(_on_body_exited)
	if altar_light == null:
		altar_light = get_node_or_null("RitualLight") as OmniLight3D
	_sync_light_state()


func is_player_nearby(player: Node3D) -> bool:
	return is_instance_valid(player) and _nearby_players.has(player)


func activate() -> bool:
	if is_lit:
		return false
	is_lit = true
	_sync_light_state()
	ritual_activated.emit(self, global_position)
	return true


func _sync_light_state() -> void:
	if altar_light == null or not is_instance_valid(altar_light):
		return
	altar_light.light_color = Color(1.0, 0.55, 0.1)
	altar_light.omni_range = 12.0
	altar_light.shadow_enabled = is_lit
	altar_light.light_energy = 10.0 if is_lit else 0.0


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _nearby_players.has(body):
		_nearby_players.append(body)


func _on_body_exited(body: Node3D) -> void:
	_nearby_players.erase(body)

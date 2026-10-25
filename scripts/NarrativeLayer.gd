extends Node3D

const MEMORY_GRAVE_CLEARANCE: float = 2.6
const MEMORY_CLEARANCE_SHAPE_SIZE: Vector3 = Vector3(1.0, 1.2, 1.0)

@export var interaction_key: Key = KEY_G
@export var dialogue_seconds: float = 8.0
@export var greeting: String = "Una voz aguarda cerca de la entrada. G para escucharla (opcional)."

@onready var hint: Label = $NarrativeHUD/Hint
@onready var panel: PanelContainer = $NarrativeHUD/Dialogue
@onready var speaker: Label = $NarrativeHUD/Dialogue/Margin/Content/Speaker
@onready var dialogue: Label = $NarrativeHUD/Dialogue/Margin/Content/Words
@onready var dismiss: Label = $NarrativeHUD/Dialogue/Margin/Content/Dismiss

var _nearest: Node3D
var _remaining: float = 0.0
var _greeted: bool = false


func _ready() -> void:
	panel.hide()
	hint.hide()
	add_to_group("narrative_layers")
	call_deferred("_ensure_memory_points_have_clear_ground")


func _ensure_memory_points_have_clear_ground() -> void:
	# Wait until static map colliders have entered the physics space before checking placements.
	await get_tree().physics_frame
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var world := get_world_3d()
	if world == null:
		return
	var open_graves: Array[Node3D] = []
	_collect_open_graves(scene_root, open_graves)
	if open_graves.is_empty():
		return
	var narrative_points := get_tree().get_nodes_in_group("narrative_points")
	for node in narrative_points:
		if not node is Node3D or str(node.get("encounter_type")) != "memory":
			continue
		var memory := node as Node3D
		if _is_memory_position_safe(memory.global_position, memory, open_graves, narrative_points):
			continue
		var safe_position: Variant = _find_nearby_safe_memory_position(memory, open_graves, narrative_points, world.direct_space_state)
		if safe_position == null:
			push_warning("No se encontró suelo despejado cerca de %s; se conservará su posición original." % memory.name)
			continue
		var resolved_position: Vector3 = safe_position
		memory.global_position = resolved_position


func _collect_open_graves(parent: Node, output: Array[Node3D]) -> void:
	for child in parent.get_children():
		if child is Node3D and str(child.name).begins_with("OpenGrave_"):
			output.append(child as Node3D)
		_collect_open_graves(child, output)


func _find_nearby_safe_memory_position(memory: Node3D, open_graves: Array[Node3D], narrative_points: Array, space_state: PhysicsDirectSpaceState3D) -> Variant:
	var origin: Vector3 = memory.global_position
	for ring in range(1, 9):
		var radius: float = float(ring) * 1.5
		for sample in range(12):
			var angle: float = TAU * float(sample) / 12.0
			var candidate: Vector3 = Vector3(origin.x + cos(angle) * radius, origin.y, origin.z + sin(angle) * radius)
			if not _has_grave_clearance(candidate, open_graves):
				continue
			if not _has_other_point_clearance(candidate, memory, narrative_points):
				continue
			var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 3.0, candidate + Vector3.DOWN * 3.0, 1)
			ray.collide_with_areas = false
			var floor_hit := space_state.intersect_ray(ray)
			if not floor_hit.is_empty():
				var floor_position: Vector3 = floor_hit["position"]
				if absf(floor_position.y) > 0.4:
					continue
				candidate.y = floor_position.y + 0.12
			elif absf(candidate.y) > 0.4:
				continue
			if not _has_memory_prop_clearance(candidate, space_state):
				continue
			return candidate
	return null


func _is_memory_position_safe(position: Vector3, memory: Node3D, open_graves: Array[Node3D], narrative_points: Array) -> bool:
	if not _has_grave_clearance(position, open_graves):
		return false
	if not _has_other_point_clearance(position, memory, narrative_points):
		return false
	var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 3.0, position + Vector3.DOWN * 3.0, 1)
	ray.collide_with_areas = false
	var world := memory.get_world_3d()
	if world == null:
		return false
	var space_state := world.direct_space_state
	var floor_hit := space_state.intersect_ray(ray)
	if floor_hit.is_empty():
		if absf(position.y) > 0.4:
			return false
	else:
		var floor_position: Vector3 = floor_hit["position"]
		if absf(floor_position.y) > 0.4:
			return false
	return _has_memory_prop_clearance(position, space_state)


func _has_grave_clearance(position: Vector3, open_graves: Array[Node3D]) -> bool:
	for grave in open_graves:
		var offset := position - grave.global_position
		offset.y = 0.0
		if offset.length() < MEMORY_GRAVE_CLEARANCE:
			return false
	return true


func _has_other_point_clearance(position: Vector3, memory: Node3D, narrative_points: Array) -> bool:
	for other in narrative_points:
		if other == memory or not other is Node3D:
			continue
		var offset: Vector3 = position - (other as Node3D).global_position
		offset.y = 0.0
		if offset.length() < 2.0:
			return false
	return true


func _has_memory_prop_clearance(position: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	var shape := BoxShape3D.new()
	shape.size = MEMORY_CLEARANCE_SHAPE_SIZE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space_state.intersect_shape(query, 8).is_empty()


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if bool(player.get("controls_frozen")) or bool(player.get("is_dead")):
		hint.hide()
		return
	if not _greeted:
		_greeted = true
		show_message("Ecos del cementerio", greeting, 6.0)
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining == 0.0:
		panel.hide()
	_nearest = null
	var nearest_distance := INF
	for point in get_tree().get_nodes_in_group("narrative_points"):
		if bool(point.get("collected")):
			continue
		var distance := player.global_position.distance_to(point.global_position)
		var point_marker: Label3D = point.get("marker")
		if point_marker != null:
			point_marker.visible = distance < float(point.get("interaction_distance")) + 0.8
		if distance <= float(point.get("interaction_distance")) and distance < nearest_distance:
			nearest_distance = distance
			_nearest = point
	hint.visible = _nearest != null
	if _nearest != null:
		hint.text = "%s · %s %s" % [OS.get_keycode_string(interaction_key), "Recordar" if _nearest.encounter_type == "memory" else "Escuchar a", _nearest.display_name]


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode != interaction_key or _nearest == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or bool(player.get("controls_frozen")) or bool(player.get("is_dead")):
		return
	var point := _nearest
	var words: String = point.interact_narrative(player)
	if not words.is_empty():
		show_message(point.display_name, words, dialogue_seconds)
	get_viewport().set_input_as_handled()


func show_message(who: String, words: String, duration: float = 6.0) -> void:
	speaker.text = who.to_upper()
	dialogue.text = words
	dismiss.text = "Puedes seguir caminando · encuentro opcional"
	_remaining = duration
	panel.show()

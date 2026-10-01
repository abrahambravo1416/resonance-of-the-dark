extends CharacterBody3D
class_name EnemyAI

signal player_caught(player: Node3D)

enum State { PATROL, INVESTIGATE, CHASE }

@export_group("References")
@export var navigation_agent: NavigationAgent3D
@export var player: CharacterBody3D
@export var patrol_points: Array[Node3D] = []

@export_group("Detection")
@export var view_distance: float = 14.0
@export_range(1.0, 180.0, 1.0) var view_angle_degrees: float = 100.0
@export var attack_range: float = 1.4
@export var noise_threshold: float = 0.55
@export var lose_player_after: float = 3.0
@export var noise_memory_seconds: float = 1.25

@export_group("Movement")
@export var patrol_speed: float = 2.0
@export var investigate_speed: float = 2.8
@export var chase_speed: float = 4.2
@export var gravity: float = 18.0

@export_group("Appearance")
@export_range(1.0, 20.0, 0.5) var head_turn_speed: float = 7.0

@export_group("Physical Shape")
@export_range(0.2, 0.8, 0.02) var collision_radius_min: float = 0.3
@export_range(0.2, 0.8, 0.02) var collision_radius_max: float = 0.48

var state: State = State.PATROL

var _patrol_index: int = 0
var _last_known_position: Vector3
var _last_noise_position: Vector3
var _noise_memory_timer: float = 0.0
var _lost_player_timer: float = 0.0
var _caught: bool = false
var _patrol_started: bool = false
var _safe_velocity: Vector3 = Vector3.ZERO
var _has_safe_velocity: bool = false
var _pumpkin_head: Node3D


func _ready() -> void:
	collision_layer = collision_layer | 1
	collision_mask = collision_mask | 1
	floor_snap_length = 0.6
	if navigation_agent == null:
		navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent != null:
		navigation_agent.path_height_offset = 0.0
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player != null and player.has_signal("noise_emitted"):
		var callback := Callable(self, "_on_player_noise_emitted")
		if not player.is_connected("noise_emitted", callback):
			player.connect("noise_emitted", callback)
	_connect_navigation_avoidance()
	if not patrol_points.is_empty():
		configure_patrol_route(patrol_points)
		start_patrol()


func configure_patrol_route(points: Array[Node3D]) -> void:
	patrol_points = points
	_patrol_index = 0
	_patrol_started = false
	if not patrol_points.is_empty():
		_last_known_position = patrol_points[0].global_position


func start_patrol() -> void:
	if navigation_agent == null:
		navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent == null or patrol_points.is_empty():
		return
	_connect_navigation_avoidance()
	_patrol_started = true
	_set_target(patrol_points[_patrol_index].global_position)


func configure_appearance(visual_root: Node3D) -> void:
	# Called by LevelBuilder after the skeleton and pumpkin head have been assembled.
	if visual_root == null:
		return
	_pumpkin_head = visual_root.find_child("PumpkinHead", true, false) as Node3D
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		add_child(collision)
	var bounds := _get_visual_bounds_in_enemy_space(visual_root)
	if bounds.size == Vector3.ZERO:
		bounds = AABB(Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 1.7, 0.7))
	var radius := clampf(maxf(bounds.size.x, bounds.size.z) * 0.3, collision_radius_min, collision_radius_max)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(bounds.size.y, radius * 2.0)
	collision.shape = shape
	collision.position = bounds.position + bounds.size * 0.5
	# The capsule bottom matches the visual feet, clamped to the floor plane.
	collision.position.y = maxf(collision.position.y, shape.height * 0.5)


func _get_visual_bounds_in_enemy_space(visual_root: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var root_inverse := global_transform.affine_inverse()
	var visuals := visual_root.find_children("*", "VisualInstance3D", true, false)
	if visual_root is VisualInstance3D:
		visuals.push_front(visual_root)
	for node in visuals:
		var visual := node as VisualInstance3D
		if visual == null:
			continue
		var relative_transform := root_inverse * visual.global_transform
		var part_bounds := relative_transform * visual.get_aabb()
		if not has_bounds:
			bounds = part_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(part_bounds)
	return bounds if has_bounds else AABB()


func _physics_process(delta: float) -> void:
	if _caught:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if player == null:
			return

	_noise_memory_timer = maxf(0.0, _noise_memory_timer - delta)
	if global_position.distance_to(player.global_position) <= attack_range:
		_catch_player()
		return

	var can_see_player := _can_see_player()
	if can_see_player:
		state = State.CHASE
		_lost_player_timer = 0.0
		_last_known_position = player.global_position
	elif state == State.CHASE:
		if _player_is_hidden():
			_lost_player_timer += delta
			if _lost_player_timer >= lose_player_after:
				state = State.PATROL
				_lost_player_timer = 0.0
		else:
			_lost_player_timer += delta
			if _lost_player_timer >= lose_player_after:
				state = State.INVESTIGATE
				_lost_player_timer = 0.0

	if state != State.CHASE and _noise_memory_timer > 0.0 and _player_noise_level() >= noise_threshold:
		state = State.INVESTIGATE

	match state:
		State.PATROL:
			_patrol(delta)
		State.INVESTIGATE:
			_investigate(delta)
		State.CHASE:
			_chase(delta)
	_update_pumpkin_facing(delta)


func _update_pumpkin_facing(delta: float) -> void:
	if _pumpkin_head == null or not is_instance_valid(_pumpkin_head):
		return
	if player == null or not is_instance_valid(player) or state == State.PATROL:
		return
	var direction_to_player := player.global_position - _pumpkin_head.global_position
	direction_to_player.y = 0.0
	if direction_to_player.length_squared() < 0.0001:
		return
	# look_at uses the model's forward (-Z); flatten the target to keep the face level.
	var current_global_rotation := _pumpkin_head.global_rotation
	_pumpkin_head.look_at(_pumpkin_head.global_position + direction_to_player, Vector3.UP)
	var target_yaw := _pumpkin_head.global_rotation.y
	_pumpkin_head.global_rotation = current_global_rotation
	var smoothed_global_rotation := current_global_rotation
	smoothed_global_rotation.x = 0.0
	smoothed_global_rotation.z = 0.0
	var blend := 1.0 - exp(-head_turn_speed * delta)
	smoothed_global_rotation.y = lerp_angle(current_global_rotation.y, target_yaw, blend)
	_pumpkin_head.global_rotation = smoothed_global_rotation


func _patrol(_delta: float) -> void:
	if patrol_points.is_empty() or not _patrol_started:
		_stop_horizontal()
		return
	if navigation_agent == null:
		return
	if navigation_agent.is_navigation_finished():
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		_set_target(patrol_points[_patrol_index].global_position)
	_move_toward_next_point(patrol_speed)


func _investigate(_delta: float) -> void:
	if navigation_agent == null:
		return
	if navigation_agent.is_navigation_finished():
		_noise_memory_timer = 0.0
		state = State.PATROL
		return
	_move_toward_next_point(investigate_speed)


func _chase(_delta: float) -> void:
	if navigation_agent == null:
		return
	if not _player_is_hidden():
		_last_known_position = player.global_position
		_set_target(_last_known_position)
	_move_toward_next_point(chase_speed)


func _move_toward_next_point(speed: float) -> void:
	if navigation_agent == null:
		return
	var next_position := navigation_agent.get_next_path_position()
	var direction := next_position - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		var desired_velocity := direction * speed
		if navigation_agent.avoidance_enabled:
			navigation_agent.velocity = desired_velocity
			var movement_velocity := _safe_velocity if _has_safe_velocity else desired_velocity
			velocity.x = movement_velocity.x
			velocity.z = movement_velocity.z
			_has_safe_velocity = false
		else:
			velocity.x = desired_velocity.x
			velocity.z = desired_velocity.z
		look_at(global_position + direction, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		navigation_agent.velocity = Vector3.ZERO
	_apply_gravity()
	move_and_slide()


func _apply_gravity() -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * get_physics_process_delta_time()


func _stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if navigation_agent != null and navigation_agent.avoidance_enabled:
		navigation_agent.velocity = Vector3.ZERO
	_apply_gravity()
	move_and_slide()


func _set_target(target_position: Vector3) -> void:
	if navigation_agent != null:
		var grounded_target := target_position
		grounded_target.y = 0.0
		navigation_agent.target_position = grounded_target


func _connect_navigation_avoidance() -> void:
	if navigation_agent == null:
		return
	navigation_agent.avoidance_enabled = true
	var callback := Callable(self, "_on_velocity_computed")
	if not navigation_agent.velocity_computed.is_connected(callback):
		navigation_agent.velocity_computed.connect(callback)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity
	_has_safe_velocity = true


func _can_see_player() -> bool:
	if player == null or _player_is_hidden():
		return false
	var eye_position := global_position + Vector3.UP * 0.9
	var player_position := player.global_position + Vector3.UP * 1.0
	var to_player := player_position - eye_position
	if to_player.length() > view_distance:
		return false
	var forward := -global_transform.basis.z
	if rad_to_deg(forward.angle_to(to_player.normalized())) > view_angle_degrees * 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye_position, player_position)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


func _player_noise_level() -> float:
	if player == null:
		return 0.0
	var value: Variant = player.get("noise_level")
	return float(value) if value != null else 0.0


func _player_is_hidden() -> bool:
	if player == null:
		return false
	var value: Variant = player.get("is_hidden")
	return bool(value) if value != null else false


func _on_player_noise_emitted(world_position: Vector3, level: float) -> void:
	if level < noise_threshold or state == State.CHASE:
		return
	_last_noise_position = world_position
	_noise_memory_timer = noise_memory_seconds
	if state != State.CHASE:
		state = State.INVESTIGATE
		_set_target(_last_noise_position)


func _catch_player() -> void:
	if _caught:
		return
	_caught = true
	if player.has_method("freeze_controls"):
		player.freeze_controls()
	player_caught.emit(player)
	if get_node_or_null("/root/LevelManager") != null:
		LevelManager.restart_current_level()

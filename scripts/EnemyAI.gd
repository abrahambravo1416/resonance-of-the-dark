extends CharacterBody3D
class_name EnemyAI

signal player_caught(player: Node3D)

enum State { PATROL, INVESTIGATE, CHASE }

const DEFAULT_VISUAL_VERTICAL_OFFSET: float = -1.0

@export_group("References")
@export var navigation_agent: NavigationAgent3D
@export var player: CharacterBody3D
@export var patrol_points: Array[Node3D] = []

@export_group("Detection")
@export var view_distance: float = 14.0
@export_range(1.0, 180.0, 1.0) var view_angle_degrees: float = 100.0
@export var attack_range: float = 1.8
@export_range(1.5, 5.0, 0.1) var attack_cooldown: float = 1.8
@export var noise_threshold: float = 0.55
@export_range(5.0, 60.0, 1.0) var noise_hearing_distance: float = 24.0
@export var lose_player_after: float = 3.0
@export var noise_memory_seconds: float = 1.25

@export_group("Lunge")
@export_range(1.0, 5.0, 0.1) var lunge_trigger_distance: float = 3.0
@export_range(4.0, 16.0, 0.5) var lunge_speed: float = 10.0
@export_range(0.08, 0.5, 0.02) var lunge_duration: float = 0.22
@export_range(0.3, 4.0, 0.1) var lunge_cooldown: float = 1.8

@export_group("Movement")
@export var patrol_speed: float = 2.0
@export var investigate_speed: float = 2.8
@export var chase_speed: float = 4.2
@export var ground_height: float = 0.0

@export_group("Appearance")
@export_range(1.0, 20.0, 0.5) var head_turn_speed: float = 7.0
@export_range(-180.0, 180.0, 1.0) var pumpkin_face_yaw_offset_degrees: float = 180.0
@export var visual_vertical_offset: float = DEFAULT_VISUAL_VERTICAL_OFFSET

@export_group("Physical Shape")
@export_range(0.2, 0.8, 0.02) var collision_radius_min: float = 0.3
@export_range(0.2, 0.8, 0.02) var collision_radius_max: float = 0.48

var state: State = State.PATROL

var _patrol_index: int = 0
var _last_known_position: Vector3
var _last_noise_position: Vector3
var _noise_memory_timer: float = 0.0
var _forced_investigation_timer: float = 0.0
var _forced_investigation_position: Vector3 = Vector3.ZERO
var _lost_player_timer: float = 0.0
var _caught: bool = false
var _escape_frozen: bool = false
var _attack_cooldown_remaining: float = 0.0
var _lunge_cooldown_remaining: float = 0.0
var _lunge_time_remaining: float = 0.0
var _lunge_active: bool = false
var _patrol_started: bool = false
var _safe_velocity: Vector3 = Vector3.ZERO
var _has_safe_velocity: bool = false
var _pumpkin_head: Node3D


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.6
	var spawn_position: Vector3 = global_position
	spawn_position.y = ground_height
	global_position = spawn_position
	velocity.y = 0.0
	_snap_to_floor_origin()
	var body_collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_collision != null:
		body_collision.position.y = 1.0
	if navigation_agent == null:
		navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent != null:
		navigation_agent.path_height_offset = 0.0
		navigation_agent.target_desired_distance = 1.0
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_connect_player_noise_signal()
	_connect_navigation_avoidance()
	if not patrol_points.is_empty():
		configure_patrol_route(patrol_points)
		start_patrol()


func configure_patrol_route(points: Array[Node3D]) -> void:
	var route_copy: Array[Node3D] = []
	for point in points:
		if point != null and is_instance_valid(point):
			route_copy.append(point)
	patrol_points = route_copy
	_patrol_index = 0
	_patrol_started = false
	if not patrol_points.is_empty():
		_last_known_position = patrol_points[0].global_position
		_last_known_position.y = ground_height


func set_player_reference(new_player: CharacterBody3D) -> void:
	if player != null and is_instance_valid(player) and player.has_signal("noise_emitted"):
		var old_callback := Callable(self, "_on_player_noise_emitted")
		if player.is_connected("noise_emitted", old_callback):
			player.disconnect("noise_emitted", old_callback)
	player = new_player
	_connect_player_noise_signal()


func _connect_player_noise_signal() -> void:
	if player == null or not is_instance_valid(player) or not player.has_signal("noise_emitted"):
		return
	var callback := Callable(self, "_on_player_noise_emitted")
	if not player.is_connected("noise_emitted", callback):
		player.connect("noise_emitted", callback)


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
	# Imported scenes can carry a positive root/bounds offset. Normalize all direct
	# visual children against their lowest rendered point, then keep the visual root
	# aligned with the CharacterBody origin at floor height.
	visual_root.position.y = 0.0
	var initial_bounds := _get_visual_bounds_in_enemy_space(visual_root)
	if initial_bounds.size != Vector3.ZERO:
		_align_visual_children_to_floor(visual_root, initial_bounds.position.y)
		var aligned_bounds := _get_visual_bounds_in_enemy_space(visual_root)
		if aligned_bounds.size != Vector3.ZERO and absf(aligned_bounds.position.y) > 0.001:
			_align_visual_children_to_floor(visual_root, aligned_bounds.position.y)
	visual_root.position.y = visual_vertical_offset
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
	shape.height = 2.0
	collision.shape = shape
	collision.position = bounds.position + bounds.size * 0.5
	# A two-meter capsule centered at Y=1 has its base exactly at floor Y=0.
	collision.position.y = 1.0


func _align_visual_children_to_floor(visual_root: Node3D, bounds_min_y: float) -> void:
	# Keep the visual container at the body origin while lifting/lowering imported
	# child scenes until their lowest rendered point is exactly at local Y=0.
	var vertical_scale: float = visual_root.scale.y
	if is_zero_approx(vertical_scale):
		return
	var local_correction: float = -bounds_min_y / vertical_scale
	for child in visual_root.get_children():
		if child is Node3D:
			child.position.y += local_correction


func _get_visual_bounds_in_enemy_space(visual_root: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	force_update_transform()
	visual_root.force_update_transform()
	var root_inverse := global_transform.affine_inverse()
	var visuals: Array[VisualInstance3D] = []
	_collect_visual_instances(visual_root, visuals)
	for node in visuals:
		node.force_update_transform()
		var relative_transform := root_inverse * node.global_transform
		var part_bounds := relative_transform * node.get_aabb()
		if not has_bounds:
			bounds = part_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(part_bounds)
	return bounds if has_bounds else AABB()


func _collect_visual_instances(root: Node, output: Array[VisualInstance3D]) -> void:
	if root is VisualInstance3D:
		output.append(root as VisualInstance3D)
	for child in root.get_children():
		_collect_visual_instances(child, output)


func _physics_process(delta: float) -> void:
	_snap_to_floor_origin()
	if _caught or _escape_frozen:
		velocity = Vector3.ZERO
		if navigation_agent != null:
			navigation_agent.velocity = Vector3.ZERO
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if player == null:
			return
	if bool(player.get("is_dead")):
		_stop_horizontal()
		return
	if _player_is_hiding_in_leaf_tree() and state == State.CHASE:
		# A leafy tree breaks line of sight immediately; search the last position
		# where the player was visible instead of continuing the lunge or attack.
		state = State.INVESTIGATE
		_lost_player_timer = 0.0
		_lunge_active = false
		_has_safe_velocity = false
		_forced_investigation_timer = 0.0
		_last_known_position.y = ground_height
		_set_target(_last_known_position)
		_stop_horizontal()

	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	_lunge_cooldown_remaining = maxf(0.0, _lunge_cooldown_remaining - delta)
	_noise_memory_timer = maxf(0.0, _noise_memory_timer - delta)
	var player_distance: float = _horizontal_distance_to_player()
	var can_reach_hidden_player: bool = state == State.CHASE and player_distance <= 3.0
	if state == State.CHASE and player_distance < attack_range and (not _player_is_hidden() or can_reach_hidden_player):
		_lunge_active = false
		_stop_horizontal()
		_update_pumpkin_facing(delta)
		if _attack_cooldown_remaining <= 0.0:
			_attack_player()
		return

	if _forced_investigation_timer > 0.0:
		_forced_investigation_timer = maxf(0.0, _forced_investigation_timer - delta)
		state = State.INVESTIGATE
		_lunge_active = false
		_set_target(_forced_investigation_position)
		if navigation_agent != null and not navigation_agent.is_navigation_finished():
			_move_toward_next_point(investigate_speed)
		else:
			_stop_horizontal()
		_update_pumpkin_facing(delta)
		return

	var can_see_player := _can_see_player()
	if can_see_player:
		state = State.CHASE
		_lost_player_timer = 0.0
		_last_known_position = _player_ground_position()
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

	if state == State.CHASE:
		if _lunge_active:
			_advance_lunge(delta)
		elif player_distance < lunge_trigger_distance and _lunge_cooldown_remaining <= 0.0:
			_start_lunge()
			_advance_lunge(delta)
		else:
			_chase(delta)
		_update_pumpkin_facing(delta)
		return
	_lunge_active = false

	match state:
		State.PATROL:
			_patrol(delta)
		State.INVESTIGATE:
			_investigate(delta)
	_update_pumpkin_facing(delta)


func _start_lunge() -> void:
	_lunge_active = true
	_lunge_time_remaining = lunge_duration
	_lunge_cooldown_remaining = lunge_cooldown
	_has_safe_velocity = false
	if navigation_agent != null:
		navigation_agent.velocity = Vector3.ZERO


func _advance_lunge(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_lunge_active = false
		return
	var direction: Vector3 = _player_ground_position() - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		_lunge_active = false
		return
	direction = direction.normalized()
	velocity.x = direction.x * lunge_speed
	velocity.z = direction.z * lunge_speed
	velocity.y = 0.0
	look_at(global_position + direction, Vector3.UP)
	move_and_slide()
	_snap_to_floor_origin()
	_update_pumpkin_facing(delta)

	var hit_player: bool = false
	for collision_index in get_slide_collision_count():
		if get_slide_collision(collision_index).get_collider() == player:
			hit_player = true
			break
	_lunge_time_remaining -= delta
	var reached_player: bool = _horizontal_distance_to_player() < attack_range
	if hit_player or reached_player:
		_lunge_active = false
		if _attack_cooldown_remaining <= 0.0:
			_attack_player()
	elif _lunge_time_remaining <= 0.0:
		_lunge_active = false
		velocity.x = 0.0
		velocity.z = 0.0
		if navigation_agent != null:
			navigation_agent.velocity = Vector3.ZERO


func _update_pumpkin_facing(delta: float) -> void:
	if _pumpkin_head == null or not is_instance_valid(_pumpkin_head):
		return
	var look_direction: Vector3
	if state == State.PATROL:
		look_direction = velocity
		look_direction.y = 0.0
		if look_direction.length_squared() < 0.0001:
			look_direction = -global_transform.basis.z
			look_direction.y = 0.0
	else:
		if player == null or not is_instance_valid(player):
			return
		look_direction = player.global_position - _pumpkin_head.global_position
		look_direction.y = 0.0
	if look_direction.length_squared() < 0.0001:
		return
	# look_at uses the model's forward (-Z); keep its target level to avoid head tilt.
	var current_global_rotation := _pumpkin_head.global_rotation
	_pumpkin_head.look_at(_pumpkin_head.global_position + look_direction, Vector3.UP)
	var target_yaw := _pumpkin_head.global_rotation.y + deg_to_rad(pumpkin_face_yaw_offset_degrees)
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
		_last_known_position = _player_ground_position()
		_set_target(_last_known_position)
	_move_toward_next_point(chase_speed)


func _player_ground_position() -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3(global_position.x, ground_height, global_position.z)
	return Vector3(player.global_position.x, ground_height, player.global_position.z)


func _horizontal_distance_to_player() -> float:
	var target: Vector3 = _player_ground_position()
	return Vector2(global_position.x - target.x, global_position.z - target.z).length()


func _move_toward_next_point(speed: float) -> void:
	if navigation_agent == null:
		return
	var next_position: Vector3 = navigation_agent.get_next_path_position()
	# The navmesh can return a point with a small vertical offset; this level uses
	# a flat floor, so movement targets stay on the configured ground plane.
	next_position.y = ground_height
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
	velocity.y = 0.0
	move_and_slide()
	_snap_to_floor_origin()


func _stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0
	if navigation_agent != null and navigation_agent.avoidance_enabled:
		navigation_agent.velocity = Vector3.ZERO
	move_and_slide()
	_snap_to_floor_origin()


func _snap_to_floor_origin() -> void:
	# Path points are flattened to the same floor height. Keep the body pinned
	# there so navigation or imported animation offsets cannot lift the enemy.
	var grounded_position: Vector3 = global_position
	grounded_position.y = ground_height
	global_position = grounded_position
	velocity.y = 0.0


func _set_target(target_position: Vector3) -> void:
	if navigation_agent != null:
		var grounded_target := target_position
		grounded_target.y = ground_height
		navigation_agent.target_position = grounded_target


func _connect_navigation_avoidance() -> void:
	if navigation_agent == null:
		return
	navigation_agent.avoidance_enabled = true
	navigation_agent.path_height_offset = 0.0
	navigation_agent.target_desired_distance = 1.0
	var callback := Callable(self, "_on_velocity_computed")
	if not navigation_agent.velocity_computed.is_connected(callback):
		navigation_agent.velocity_computed.connect(callback)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity
	_has_safe_velocity = true


func _can_see_player() -> bool:
	if player == null:
		return false
	if _player_is_hiding_in_leaf_tree():
		return false
	if _player_is_hiding():
		var already_close_in_chase: bool = state == State.CHASE and _horizontal_distance_to_player() <= 3.0
		# Cover conceals the player from a fresh sighting. A pursuer already on
		# their heels can keep tracking them at close range.
		if already_close_in_chase:
			return true
		return false
	if _player_is_hidden():
		return false
	var eye_position := global_position + Vector3.UP * 0.9
	# Carrying a relic is not a crouch/stealth state. Aim at the player's torso
	# regardless of the slow carry speed or the visual prop attached to the camera.
	var player_position: Vector3 = player.global_position + Vector3.UP * _player_detection_height()
	var to_player := player_position - eye_position
	if to_player.length() > view_distance:
		return false
	var forward := -global_transform.basis.z
	if rad_to_deg(forward.angle_to(to_player.normalized())) > view_angle_degrees * 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye_position, player_position)
	query.collision_mask = 1
	var excluded_rids: Array[RID] = [get_rid()]
	if _player_is_carrying_relic():
		var carried_relic: Variant = player.get("carried_absolute_ritual_relic")
		if carried_relic is Node:
			_append_collision_rids(carried_relic as Node, excluded_rids)
	query.exclude = excluded_rids
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


func _player_detection_height() -> float:
	if _player_is_carrying_relic():
		return 1.0
	var crouching: Variant = player.get("is_crouching")
	return 0.65 if crouching != null and bool(crouching) else 1.0


func _player_is_carrying_relic() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var carrying: Variant = player.get("is_carrying_absolute_ritual_relic")
	return bool(carrying) if carrying != null else false


func _append_collision_rids(root: Node, output: Array[RID]) -> void:
	if root is CollisionObject3D:
		output.append((root as CollisionObject3D).get_rid())
	for child in root.get_children():
		_append_collision_rids(child, output)


func _player_noise_level() -> float:
	if player == null:
		return 0.0
	var value: Variant = player.get("noise_level")
	return float(value) if value != null else 0.0


func _player_is_hidden() -> bool:
	if player == null:
		return false
	var zone_hidden: Variant = player.get("is_hidden")
	var cover_hidden: Variant = player.get("is_hiding")
	return (bool(zone_hidden) if zone_hidden != null else false) or (bool(cover_hidden) if cover_hidden != null else false)


func _player_is_hiding() -> bool:
	if player == null:
		return false
	var value: Variant = player.get("is_hiding")
	return bool(value) if value != null else false


func _player_is_hiding_in_leaf_tree() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var hiding_value: Variant = player.get("is_hiding")
	var cover_type: Variant = player.get("current_cover_type")
	return bool(hiding_value) and cover_type == "leaf_tree"


func _on_player_noise_emitted(world_position: Vector3, level: float) -> void:
	if level < noise_threshold or state == State.CHASE:
		return
	var sound_delta: Vector3 = world_position - global_position
	sound_delta.y = 0.0
	var hearing_radius: float = noise_hearing_distance * clampf(level, noise_threshold, 1.0)
	if sound_delta.length() > hearing_radius:
		return
	_last_noise_position = world_position
	_noise_memory_timer = noise_memory_seconds
	if state != State.CHASE:
		state = State.INVESTIGATE
		_set_target(_last_noise_position)


func investigate_position(world_position: Vector3, duration: float = 5.0) -> void:
	if state == State.CHASE and _horizontal_distance_to_player() <= attack_range:
		return
	_forced_investigation_position = Vector3(world_position.x, ground_height, world_position.z)
	_forced_investigation_timer = maxf(_forced_investigation_timer, duration)
	_noise_memory_timer = maxf(_noise_memory_timer, duration)
	_lost_player_timer = 0.0
	_lunge_active = false
	state = State.INVESTIGATE
	_set_target(_forced_investigation_position)


func freeze_for_escape() -> void:
	_escape_frozen = true
	_lunge_active = false
	velocity = Vector3.ZERO
	if navigation_agent != null:
		navigation_agent.velocity = Vector3.ZERO


func _attack_player() -> void:
	if player == null or not is_instance_valid(player) or not player.has_method("take_damage"):
		return
	_attack_cooldown_remaining = attack_cooldown
	if player.has_method("apply_knockback"):
		player.call("apply_knockback", global_position)
	player.take_damage(1)

extends CharacterBody3D
class_name PlayerController

signal noise_emitted(world_position: Vector3, level: float)
signal item_collected(item_name: String, collected: int, required: int)
signal health_changed(current_health: int, max_health: int)
signal player_died

@export_group("References")
@export var camera: Camera3D
@export var interaction_ray: RayCast3D

@export_group("Movement")
@export var walk_speed: float = 3.5
@export var sprint_speed: float = 6.5
@export var jump_velocity: float = 7.0
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 18.0
@export var walk_noise_level: float = 0.25
@export var sprint_noise_level: float = 1.0
@export var crouch_noise_level: float = 0.08
@export var noise_emission_interval: float = 0.35
@export_range(0.2, 0.6, 0.02) var collision_radius: float = 0.3
@export_range(1.0, 2.0, 0.05) var collision_height: float = 1.7

@export_group("Inventory")
@export_range(0, 100, 1) var total_items_needed: int = 4

@export_group("Health")
@export var max_health: int = 4
@export var current_health: int = 4
@export_range(1.0, 60.0, 0.5) var regeneration_delay: float = 10.0

var is_hidden: bool = false
var is_running: bool = false
var is_crouching: bool = false
var noise_level: float = 0.0
var items_collected: int = 0
var controls_frozen: bool = false
var is_dead: bool = false

var _noise_timer: float = 0.0
var _pitch: float = 0.0
var _standing_camera_height: float = 0.55
var _regeneration_timer: float = 0.0


func _ready() -> void:
	add_to_group("player")
	max_health = maxi(1, max_health)
	current_health = clampi(current_health, 0, max_health)
	_ensure_input_actions()
	_configure_collision_shape()
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		_standing_camera_height = camera.position.y
	if interaction_ray == null and camera != null:
		interaction_ray = camera.get_node_or_null("InteractionRay") as RayCast3D
	if interaction_ray != null:
		interaction_ray.add_exception(self)
		interaction_ray.collide_with_areas = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if get_node_or_null("/root/LevelManager") != null:
		LevelManager.register_player(self)
	if current_health <= 0:
		_die()


func _process(delta: float) -> void:
	if is_dead or current_health >= max_health:
		_regeneration_timer = 0.0
		return
	_regeneration_timer -= delta
	if _regeneration_timer <= 0.0:
		current_health = mini(current_health + 1, max_health)
		health_changed.emit(current_health, max_health)
		_regeneration_timer = regeneration_delay if current_health < max_health else 0.0


func take_damage(amount: int = 1) -> void:
	if is_dead or amount <= 0:
		return
	var previous_health := current_health
	current_health = maxi(0, current_health - amount)
	if current_health == previous_health:
		return
	_regeneration_timer = regeneration_delay
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	freeze_controls()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_died.emit()


func _unhandled_input(event: InputEvent) -> void:
	if controls_frozen:
		return
	if event is InputEventMouseMotion and camera != null:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		camera.rotation.x = _pitch
	if event.is_action_pressed("interact"):
		_interact_with_target()


func _physics_process(delta: float) -> void:
	if controls_frozen:
		velocity = Vector3.ZERO
		return
	_update_crouch_state(Input.is_action_pressed("crouch"))

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward_strength := maxf(-input_vector.y, 0.0)
	var backward_strength := maxf(input_vector.y, 0.0)
	var move_direction := transform.basis.x * input_vector.x
	move_direction += -transform.basis.z * forward_strength
	move_direction += transform.basis.z * backward_strength
	move_direction = move_direction.normalized()
	is_running = not is_crouching and input_vector.length_squared() > 0.0 and Input.is_action_pressed("sprint")
	var current_speed := walk_speed * 0.5 if is_crouching else sprint_speed if is_running else walk_speed
	velocity.x = move_direction.x * current_speed
	velocity.z = move_direction.z * current_speed

	if is_on_floor():
		velocity.y = jump_velocity if not is_crouching and Input.is_action_just_pressed("jump") else 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_update_noise(delta, input_vector.length_squared() > 0.0)


func _update_noise(delta: float, is_moving: bool) -> void:
	noise_level = crouch_noise_level if is_moving and is_crouching else sprint_noise_level if is_moving and is_running else walk_noise_level if is_moving else 0.0
	if noise_level <= 0.0:
		_noise_timer = 0.0
		return
	_noise_timer += delta
	if _noise_timer >= noise_emission_interval:
		_noise_timer = 0.0
		noise_emitted.emit(global_position, noise_level)


func _interact_with_target() -> void:
	if interaction_ray == null or not interaction_ray.is_colliding():
		return
	var target := interaction_ray.get_collider()
	if target != null and target.has_method("interact"):
		target.interact(self)


func collect_item(item_name: String) -> void:
	items_collected += 1
	item_collected.emit(item_name, items_collected, total_items_needed)
	if get_node_or_null("/root/LevelManager") != null:
		LevelManager.check_level_completion()


func set_hidden(hidden: bool) -> void:
	is_hidden = hidden


func orient_toward(world_target: Vector3) -> void:
	var horizontal_target := world_target
	horizontal_target.y = global_position.y
	if global_position.distance_squared_to(horizontal_target) > 0.0001:
		look_at(horizontal_target, Vector3.UP)
	_pitch = 0.0
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.rotation = Vector3.ZERO


func freeze_controls() -> void:
	controls_frozen = true
	is_running = false
	noise_level = 0.0
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _configure_collision_shape() -> void:
	collision_layer = collision_layer | 1
	collision_mask = collision_mask | 1
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		add_child(collision)
	var capsule := CapsuleShape3D.new()
	capsule.radius = collision_radius
	capsule.height = maxf(collision_height, collision_radius * 2.0)
	collision.shape = capsule
	collision.position.y = 0.0


func _update_crouch_state(wants_to_crouch: bool) -> void:
	if is_crouching == wants_to_crouch:
		return
	is_crouching = wants_to_crouch
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D if collision != null else null
	if capsule != null:
		var target_height := collision_height * (0.5 if is_crouching else 1.0)
		capsule.height = maxf(target_height, collision_radius * 2.0)
		collision.position.y = -(collision_height - capsule.height) * 0.5 if is_crouching else 0.0
	if camera != null:
		camera.position.y = _standing_camera_height * (0.5 if is_crouching else 1.0)


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("interact", KEY_E)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("crouch", KEY_CTRL)
	_add_key_action("crouch", KEY_C)


func _add_key_action(action_name: StringName, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == key:
			return
	var key_event = InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action_name, key_event)

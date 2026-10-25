extends CharacterBody3D
class_name PlayerController

signal noise_emitted(world_position: Vector3, level: float)
signal item_collected(item_name: String, collected: int, required: int)
signal health_changed(current_health: int, max_health: int)
signal player_died
signal ritual_progress_changed(completed: int, required: int)
signal cemetery_exit_unlocked

const ALTAR_MARKER_COLOR_HEX: String = "#FFAA00"
const EXIT_GATE_MARKER_COLOR_HEX: String = "#00FF66"
const PUMPKIN_MARKER_COLOR_HEX: String = "#FF8000"
const SKULL_MARKER_COLOR_HEX: String = "#3399FF"
const ABSOLUTE_RELIC_MARKER_COLOR_HEX: String = "#FFB6C1"
const RITUAL_DELIVERY_MARKER_COLOR_HEX: String = "#40E0D0"
const ABSOLUTE_RELIC_MARKER_COLOR: Color = Color(1.0, 0.714, 0.757, 1.0)
const RITUAL_DELIVERY_MARKER_COLOR: Color = Color(0.251, 0.878, 0.816, 1.0)
const PUMPKINS_REQUIRED: int = 7
const FINAL_LEVEL_PUMPKINS_REQUIRED: int = 4
const SFX_MENU_CLICK: AudioStreamWAV = preload("res://audio/Efectos cortos/click_menu.wav")
const SFX_HIDE: AudioStreamWAV = preload("res://audio/Efectos cortos/esconder_salir_escondite.wav")
const SFX_PUMPKIN: AudioStreamWAV = preload("res://audio/Efectos cortos/recoger_calabazas.wav")
const SFX_HEALTH_SKULL_PICKUP: AudioStreamWAV = preload("res://audio/Efectos cortos/curarse_con_craneos.wav")
const SFX_ENEMY_HIT: AudioStreamWAV = preload("res://audio/Efectos cortos/golpeo_de_enemigo.wav")
const SFX_EXIT_UNLOCK: AudioStreamWAV = preload("res://audio/Efectos cortos/desbloquear_salida.wav")
const SFX_LOSE: AudioStreamWAV = preload("res://audio/Efectos cortos/lose.wav")
const SFX_WALK: AudioStreamWAV = preload("res://audio/Efectos cortos/caminar.wav")
const TRANSITION_SKIP_INPUT_SCRIPT: Script = preload("res://scripts/TransitionSkipInput.gd")

@export_group("Editable scenes")
@export var intro_scenes: Array[PackedScene] = [preload("res://scenes/ui/LevelIntro_01.tscn"), preload("res://scenes/ui/LevelIntro_02.tscn"), preload("res://scenes/ui/LevelIntro_03.tscn"), preload("res://scenes/ui/LevelIntro_04.tscn")]
@export var level_complete_scene: PackedScene = preload("res://scenes/ui/LevelComplete.tscn")
@export var victory_scene: PackedScene = preload("res://scenes/ui/Victory.tscn")
@export var enemy_marker_scene: PackedScene = preload("res://scenes/ui/RadarEnemyMarker.tscn")
@export var skull_marker_scene: PackedScene = preload("res://scenes/ui/RadarSkullMarker.tscn")
@export var pumpkin_marker_scene: PackedScene = preload("res://scenes/ui/RadarPumpkinMarker.tscn")
@export var relic_marker_scene: PackedScene = preload("res://scenes/ui/RadarRelicMarker.tscn")
@export var sound_effect_scene: PackedScene = preload("res://scenes/ui/SoundEffect.tscn")
@export var hiding_animation: AnimationPlayer
@export var hiding_motion: Node3D
@export var camera_shake: Node3D

@export_group("References")
@export var camera: Camera3D
@export var interaction_ray: RayCast3D
@export var hiding_ray: RayCast3D

@export_group("Movement")
@export var walk_speed: float = 3.5
@export var sprint_speed: float = 6.5
@export var jump_velocity: float = 7.0
@export var coyote_time: float = 0.15
@export var jump_buffer_time: float = 0.15
@export var shake_decay: float = 5.0
@export var walk_step_frequency: float = 12.0
@export var walk_step_amplitude: float = 0.05
@export var run_step_frequency: float = 16.0
@export var run_step_amplitude: float = 0.09
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

@export_group("Threat Radar")
@export_range(1.0, 20.0, 0.5) var critical_enemy_distance: float = 5.0

@export_group("Hiding")
@export_range(0.5, 4.0, 0.1) var hiding_detection_distance: float = 2.0
@export_range(0.25, 0.75, 0.05) var hiding_camera_height_ratio: float = 0.45
@export_range(0.05, 0.4, 0.01) var cover_approach_duration: float = 0.16
@export_range(0.1, 0.2, 0.01) var cover_surface_clearance: float = 0.15
@export_range(0.08, 0.3, 0.01) var hiding_collision_radius: float = 0.1
@export_range(0.25, 1.0, 0.05) var cover_exit_distance: float = 0.5

@export_group("Rituals")
@export_range(0.5, 3.0, 0.1) var ritual_interaction_distance: float = 2.0

@export_group("Damage Feedback")
@export_range(0.2, 0.8, 0.05) var damage_flash_alpha: float = 0.5
@export_range(0.05, 0.5, 0.01) var damage_feedback_duration: float = 0.2
@export_range(0.01, 0.2, 0.01) var camera_shake_intensity: float = 0.07

@export_group("Knockback")
@export_range(0.5, 8.0, 0.25) var knockback_strength: float = 3.25
@export_range(0.05, 0.5, 0.01) var knockback_duration: float = 0.2

var is_hidden: bool = false
var is_hiding: bool = false
var breath_label: Label
var current_cover_type: String = ""
var is_running: bool = false
var is_crouching: bool = false
var noise_level: float = 0.0
var items_collected: int = 0
var collected_item_ids: Array[String] = []
var rituals_completed: int = 0
var pumpkins_collected: int = 0
var absolute_ritual_relics_delivered: int = 0
var total_absolute_ritual_relics: int = 0
var is_carrying_absolute_ritual_relic: bool = false
var carried_absolute_ritual_relic: Node3D
var total_rituals_required: int = 4
var current_level_number: int = 1
var ritual_shrines: Array[RitualAltar] = []
var enemies: Array[CharacterBody3D] = []
var exit_unlocked: bool = false
var controls_frozen: bool = false
var is_dead: bool = false

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var shake_strength: float = 0.0
var rng = RandomNumberGenerator.new()
var _screenshake_offset: Vector2 = Vector2.ZERO
var step_cycle: float = 0.0
@onready var initial_cam_y: float = $Camera3D.position.y
var _head_bob_offset: Vector3 = Vector3.ZERO
var _head_bob_roll: float = 0.0
var _noise_timer: float = 0.0
var _pitch: float = 0.0
var _standing_camera_height: float = 0.55
var _camera_base_position: Vector3 = Vector3.ZERO
var _camera_base_rotation: Vector3 = Vector3.ZERO
var _hiding_camera_weight: float = 0.0
var _exiting_cover: Dictionary = {}
var _regeneration_timer: float = 0.0
var _hidden_by_zone: bool = false
var _hiding_target: Node3D
var _hiding_collision_point: Vector3 = Vector3.ZERO
var _hiding_collision_normal: Vector3 = Vector3.ZERO
var _has_pre_hiding_transform: bool = false
var _hiding_approach_tween: Tween
var _hiding_camera_tween: Tween
var _hiding_collision_was_disabled: bool = false
var _breath_time_remaining: float = 5.0
var _hiding_overlay_layer: CanvasLayer
var _hiding_overlay: ColorRect
var _cover_transition_active: bool = false
var _knockback_velocity: Vector3 = Vector3.ZERO
var _knockback_time_remaining: float = 0.0
var _radar_layer: CanvasLayer
var _radar_root: Control
var _radar_arrow_area: Control
var _radar_circle: Panel
var _radar_arrow: Label
var _radar_enemy_arrows: Array[Label] = []
var _radar_skull_markers: Dictionary = {}
var _radar_pumpkin_markers: Dictionary = {}
var _radar_absolute_relic_markers: Dictionary = {}
var _radar_exit_gate_marker: Label
var _radar_relic_delivery_marker: Label
var _radar_center_glow: Panel
var _radar_center_dot: Panel
var _radar_altar_markers: Array[Label] = []
var _radar_exit_gate_target: Node3D
var _radar_exit_gate_open: bool = false
var _radar_distance_label: Label
var _radar_alert_label: Label
var _radar_alert_settings: LabelSettings
var _radar_distance_settings: LabelSettings
var _radar_flash_time: float = 0.0
var _radar_alert_flash_time: float = 0.0
var _interaction_prompt: Label
var _ritual_counter_label: Label
var _ritual_mission_label: RichTextLabel
var _pumpkin_counter_label: RichTextLabel
var _altar_mission_title_label: RichTextLabel
var _altar_progress_label: RichTextLabel
var _healing_mission_label: RichTextLabel
var _absolute_ritual_title_label: RichTextLabel
var _absolute_ritual_progress_label: RichTextLabel
var _escape_mission_title_label: RichTextLabel
var _escape_mission_label: RichTextLabel
var _objective_container: VBoxContainer
var _objective_counter_font: Font
var _objective_instruction_font: Font
var _pumpkin_lock_message: Label
var _pumpkin_lock_timer: Timer
var _exit_gate_nearby: bool = false
var _has_escaped: bool = false
var _purification_sequence_active: bool = false
var _purification_sequence_finished: bool = false
var _campaign_autosave_elapsed: float = 0.0
var _victory_screen_layer: CanvasLayer
var _level_score_seconds: int = 0
var _level_score_points: int = 0
var _is_new_high_score: bool = false
var _damage_flash_layer: CanvasLayer
var _damage_flash_rect: ColorRect
var _damage_flash_tween: Tween
var _camera_shake_tween: Tween
var _purification_flash_layer: CanvasLayer
var _purification_flash_rect: ColorRect
var _purification_flash_tween: Tween
var walk_audio_player: AudioStreamPlayer
var _level_2_intro_layer: CanvasLayer
var _level_2_intro_timer: Timer
var _level_2_intro_countdown_label: Label
var countdown_time: int = 10


func _ready() -> void:
	rng.randomize()
	add_to_group("player")
	max_health = maxi(1, max_health)
	current_health = clampi(current_health, 0, max_health)
	_ensure_input_actions()
	_bind_authored_nodes(self)
	_radar_alert_settings = _radar_alert_label.label_settings
	_radar_distance_settings = _radar_distance_label.label_settings
	_pumpkin_lock_timer.timeout.connect(_hide_pumpkin_lock_message)
	_configure_collision_shape()
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		_standing_camera_height = initial_cam_y
		_camera_base_position = camera.position
		_camera_base_rotation = camera.rotation
		_pitch = camera.rotation.x
	if hiding_animation != null:
		hiding_animation.animation_finished.connect(_on_hiding_animation_finished)
	_refresh_radar_enemies()
	if interaction_ray == null and camera != null:
		interaction_ray = camera.get_node_or_null("InteractionRay") as RayCast3D
	if interaction_ray != null:
		interaction_ray.add_exception(self)
		interaction_ray.collide_with_areas = true
	_configure_hiding_ray()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if get_node_or_null("/root/LevelManager") != null:
		get_node("/root/LevelManager").call("register_player", self)
	if current_health <= 0:
		_die()


func _process(delta: float) -> void:
	_campaign_autosave_elapsed += delta
	if _campaign_autosave_elapsed >= 20.0:
		_persist_campaign_level_progress()
	if shake_strength > 0.0:
		shake_strength = move_toward(shake_strength, 0.0, shake_decay * delta)
		_screenshake_offset = Vector2(
			rng.randf_range(-shake_strength, shake_strength),
			rng.randf_range(-shake_strength, shake_strength)
		) * 0.1
	else:
		_screenshake_offset = Vector2.ZERO
	_apply_camera_pose()
	_update_threat_radar(delta)
	_update_interaction_prompt()
	if is_hiding:
		_breath_time_remaining = maxf(0.0, _breath_time_remaining - delta)
		if breath_label != null:
			breath_label.text = "Aguantando la respiración  %d..." % ceili(_breath_time_remaining)
	if is_hiding and is_zero_approx(_breath_time_remaining):
		_set_hiding(false, null, true)
	if is_dead or current_health >= max_health or current_level_number >= 2:
		_regeneration_timer = 0.0
		return
	_regeneration_timer -= delta
	if _regeneration_timer <= 0.0:
		current_health = mini(current_health + 1, max_health)
		_log("health_restored", {"amount": 1, "health": current_health, "source": "passive_regeneration"})
		health_changed.emit(current_health, max_health)
		_regeneration_timer = regeneration_delay if current_health < max_health else 0.0


func add_screenshake(amount: float) -> void:
	shake_strength = clamp(shake_strength + amount, 0.0, 1.0)


func _update_head_bob(delta: float, moving_on_ground: bool) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if moving_on_ground and is_on_floor() and horizontal_speed > 0.2:
		var current_frequency: float = run_step_frequency if is_running else walk_step_frequency
		var current_amplitude: float = run_step_amplitude if is_running else walk_step_amplitude
		step_cycle += delta * current_frequency
		_head_bob_offset.y = sin(step_cycle) * current_amplitude
		_head_bob_offset.x = cos(step_cycle * 0.5) * (current_amplitude * 0.5)
		_head_bob_roll = cos(step_cycle * 0.5) * deg_to_rad(1.2)
	else:
		step_cycle = 0.0
		var return_weight := clampf(delta * 10.0, 0.0, 1.0)
		_head_bob_offset = _head_bob_offset.lerp(Vector3.ZERO, return_weight)
		_head_bob_roll = lerpf(_head_bob_roll, 0.0, return_weight)


func set_enemies(enemy_list: Array[CharacterBody3D]) -> void:
	enemies.clear()
	for enemy_node in enemy_list:
		if enemy_node != null and is_instance_valid(enemy_node) and not enemies.has(enemy_node):
			enemies.append(enemy_node)
	_refresh_radar_enemies()


func _refresh_radar_enemies() -> void:
	var active_enemies: Array[CharacterBody3D] = []
	for enemy_node in enemies:
		if enemy_node != null and is_instance_valid(enemy_node) and not active_enemies.has(enemy_node):
			active_enemies.append(enemy_node)
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy_node := node as CharacterBody3D
		if enemy_node != null and is_instance_valid(enemy_node) and not active_enemies.has(enemy_node):
			active_enemies.append(enemy_node)
	enemies = active_enemies


func _ensure_enemy_radar_arrows(required_count: int) -> void:
	while _radar_enemy_arrows.size() < required_count:
		var arrow := enemy_marker_scene.instantiate() as Label
		arrow.name = "ThreatArrow_%02d" % (_radar_enemy_arrows.size() + 1)
		_radar_arrow_area.add_child(arrow)
		_radar_enemy_arrows.append(arrow)


func _update_threat_radar(delta: float) -> void:
	if _radar_root == null:
		return
	_radar_root.visible = true
	_refresh_radar_enemies()
	_ensure_enemy_radar_arrows(enemies.size())
	_refresh_ritual_shrines()
	_update_radar_alert_state(delta)
	if camera == null or not is_instance_valid(camera):
		for arrow in _radar_enemy_arrows:
			arrow.visible = false
		for marker in _radar_altar_markers:
			marker.visible = false
		_radar_exit_gate_marker.visible = false
		_radar_relic_delivery_marker.visible = false
		for marker in _radar_absolute_relic_markers.values():
			if is_instance_valid(marker):
				marker.visible = false
		return
	_update_ritual_radar_markers()
	_update_exit_gate_radar_marker()
	var radar_size: Vector2 = _radar_arrow_area.size
	var radar_center: Vector2 = radar_size * 0.5
	_update_health_skull_radar_markers(radar_center)
	_update_pumpkin_radar_markers(radar_center)
	_update_absolute_relic_radar_markers(radar_center)
	_update_relic_delivery_radar_marker(radar_center)
	var closest_distance: float = INF
	for arrow_index in _radar_enemy_arrows.size():
		var arrow: Label = _radar_enemy_arrows[arrow_index]
		arrow.visible = false
		if arrow_index >= enemies.size():
			continue
		var enemy_node: CharacterBody3D = enemies[arrow_index]
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		var distance: float = global_position.distance_to(enemy_node.global_position)
		closest_distance = minf(closest_distance, distance)
		var toward_enemy: Vector3 = enemy_node.global_position - global_position
		toward_enemy.y = 0.0
		if toward_enemy.length_squared() < 0.0001:
			continue
		var angle: float = _radar_relative_angle(enemy_node.global_position)
		var arrow_center: Vector2 = _world_to_radar_position(enemy_node.global_position, radar_center)
		arrow.pivot_offset = arrow.size * 0.5
		arrow.position = arrow_center - arrow.size * 0.5
		arrow.rotation = angle + PI
		arrow.visible = true
		if distance < critical_enemy_distance:
			_radar_flash_time += delta
			var blink: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_radar_flash_time * 10.0 + float(arrow_index)))
			arrow.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
			arrow.modulate.a = blink
		else:
			arrow.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.9))
			arrow.modulate.a = 1.0
	var distance_text: String = "%.1f m" % closest_distance if closest_distance < INF else "--.- m"
	_radar_distance_label.text = "LEJANÍA DEL ENEMIGO: %s" % distance_text


func _update_health_skull_radar_markers(radar_center: Vector2) -> void:
	if current_level_number < 2:
		for marker in _radar_skull_markers.values():
			if is_instance_valid(marker):
				marker.queue_free()
		_radar_skull_markers.clear()
		return
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("get_active_skulls"):
		return
	var active_skulls: Array = level_builder.call("get_active_skulls")
	var live_ids: Dictionary = {}
	for skull in active_skulls:
		if not is_instance_valid(skull) or not (skull is Node3D):
			continue
		var skull_node := skull as Node3D
		var marker_id: int = skull_node.get_instance_id()
		live_ids[marker_id] = true
		var marker := _radar_skull_markers.get(marker_id) as Label
		if marker == null or not is_instance_valid(marker):
			marker = skull_marker_scene.instantiate() as Label
			marker.name = "HealthSkullMarker_%d" % marker_id
			_radar_arrow_area.add_child(marker)
			_radar_skull_markers[marker_id] = marker
		var toward_skull: Vector3 = skull_node.global_position - global_position
		toward_skull.y = 0.0
		if toward_skull.length_squared() < 0.0001:
			marker.visible = false
			continue
		var marker_center: Vector2 = _world_to_radar_position(skull_node.global_position, radar_center)
		marker.position = marker_center - marker.size * 0.5
		marker.modulate.a = 0.82 + 0.18 * (0.5 + 0.5 * sin(_radar_flash_time * 8.0 + float(marker_id % 10)))
		marker.visible = true
	for marker_id in _radar_skull_markers.keys().duplicate():
		if live_ids.has(marker_id):
			continue
		var stale_marker := _radar_skull_markers[marker_id] as Label
		if is_instance_valid(stale_marker):
			stale_marker.queue_free()
		_radar_skull_markers.erase(marker_id)


func _update_pumpkin_radar_markers(radar_center: Vector2) -> void:
	if current_level_number < 3:
		for marker in _radar_pumpkin_markers.values():
			if is_instance_valid(marker):
				marker.queue_free()
		_radar_pumpkin_markers.clear()
		return
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("get_active_pumpkins"):
		return
	var active_pumpkins: Array = level_builder.call("get_active_pumpkins")
	var live_ids: Dictionary = {}
	for pumpkin in active_pumpkins:
		if not is_instance_valid(pumpkin) or not (pumpkin is Node3D):
			continue
		var pumpkin_node := pumpkin as Node3D
		var marker_id: int = pumpkin_node.get_instance_id()
		live_ids[marker_id] = true
		var marker := _radar_pumpkin_markers.get(marker_id) as Label
		if marker == null or not is_instance_valid(marker):
			marker = pumpkin_marker_scene.instantiate() as Label
			marker.name = "PumpkinMarker_%d" % marker_id
			_radar_arrow_area.add_child(marker)
			_radar_pumpkin_markers[marker_id] = marker
		var toward_pumpkin: Vector3 = pumpkin_node.global_position - global_position
		toward_pumpkin.y = 0.0
		if toward_pumpkin.length_squared() < 0.0001:
			marker.visible = false
			continue
		var marker_center: Vector2 = _world_to_radar_position(pumpkin_node.global_position, radar_center)
		marker.position = marker_center - marker.size * 0.5
		marker.modulate.a = 0.88 + 0.12 * (0.5 + 0.5 * sin(_radar_flash_time * 7.0 + float(marker_id % 10)))
		marker.visible = true
	for marker_id in _radar_pumpkin_markers.keys().duplicate():
		if live_ids.has(marker_id):
			continue
		var stale_marker := _radar_pumpkin_markers[marker_id] as Label
		if is_instance_valid(stale_marker):
			stale_marker.queue_free()
		_radar_pumpkin_markers.erase(marker_id)


func _update_absolute_relic_radar_markers(radar_center: Vector2) -> void:
	if current_level_number != 4:
		for marker in _radar_absolute_relic_markers.values():
			if is_instance_valid(marker):
				marker.queue_free()
		_radar_absolute_relic_markers.clear()
		return
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("get_absolute_ritual_relics"):
		return
	var relics: Array = level_builder.call("get_absolute_ritual_relics")
	var live_ids: Dictionary = {}
	for relic in relics:
		if not is_instance_valid(relic) or not (relic is Node3D):
			continue
		var relic_node := relic as Node3D
		if bool(relic_node.get_meta("carried", false)) or bool(relic_node.get_meta("delivered", false)):
			continue
		var marker_id: int = relic_node.get_instance_id()
		live_ids[marker_id] = true
		var marker := _radar_absolute_relic_markers.get(marker_id) as Label
		if marker == null or not is_instance_valid(marker):
			marker = relic_marker_scene.instantiate() as Label
			marker.name = "AbsoluteRitualRelicMarker_%d" % marker_id
			_radar_arrow_area.add_child(marker)
			_radar_absolute_relic_markers[marker_id] = marker
		var toward_relic: Vector3 = relic_node.global_position - global_position
		toward_relic.y = 0.0
		if toward_relic.length_squared() < 0.0001:
			marker.visible = false
			continue
		var marker_center: Vector2 = _world_to_radar_position(relic_node.global_position, radar_center)
		marker.position = marker_center - marker.size * 0.5
		marker.modulate.a = 0.9 + 0.1 * (0.5 + 0.5 * sin(_radar_flash_time * 6.0 + float(marker_id % 10)))
		marker.visible = true
	for marker_id in _radar_absolute_relic_markers.keys().duplicate():
		if live_ids.has(marker_id):
			continue
		var stale_marker := _radar_absolute_relic_markers[marker_id] as Label
		if is_instance_valid(stale_marker):
			stale_marker.queue_free()
		_radar_absolute_relic_markers.erase(marker_id)


func _update_relic_delivery_radar_marker(radar_center: Vector2) -> void:
	if _radar_relic_delivery_marker == null:
		return
	_radar_relic_delivery_marker.visible = false
	if current_level_number != 4 or not is_carrying_absolute_ritual_relic:
		return
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("get_absolute_ritual_delivery_position"):
		return
	var delivery_position: Vector3 = level_builder.call("get_absolute_ritual_delivery_position")
	var toward_delivery: Vector3 = delivery_position - global_position
	toward_delivery.y = 0.0
	if toward_delivery.length_squared() < 0.0001:
		_radar_relic_delivery_marker.position = radar_center - _radar_relic_delivery_marker.size * 0.5
	else:
		var marker_center: Vector2 = _world_to_radar_position(delivery_position, radar_center)
		_radar_relic_delivery_marker.position = marker_center - _radar_relic_delivery_marker.size * 0.5
	_radar_relic_delivery_marker.visible = true
	_radar_relic_delivery_marker.modulate.a = 0.9 + 0.1 * (0.5 + 0.5 * sin(_radar_flash_time * 5.0))


func set_ritual_shrines(altars: Array[RitualAltar]) -> void:
	ritual_shrines.clear()
	for altar in altars:
		if is_instance_valid(altar):
			ritual_shrines.append(altar)
	_refresh_ritual_shrines()
	_update_ritual_radar_markers()


func configure_level(level_number: int, ritual_count: int, absolute_relic_count: int = 0) -> void:
	current_level_number = clampi(level_number, 1, 4)
	total_rituals_required = maxi(1, ritual_count)
	total_absolute_ritual_relics = maxi(0, absolute_relic_count) if current_level_number == 4 else 0
	items_collected = 0
	collected_item_ids.clear()
	rituals_completed = 0
	pumpkins_collected = 0
	absolute_ritual_relics_delivered = 0
	is_carrying_absolute_ritual_relic = false
	carried_absolute_ritual_relic = null
	exit_unlocked = false
	_purification_sequence_active = false
	_purification_sequence_finished = false
	if _pumpkin_counter_label != null:
		_pumpkin_counter_label.visible = current_level_number >= 3
	if _altar_progress_label != null:
		_altar_progress_label.visible = true
	update_objective_ui()


func restore_mission_progress(progress: Dictionary) -> void:
	items_collected = maxi(0, int(progress.get("items_collected", 0)))
	collected_item_ids.clear()
	var saved_item_ids: Variant = progress.get("collected_item_ids", [])
	if saved_item_ids is Array:
		for item_id in saved_item_ids:
			collected_item_ids.append(str(item_id))
	pumpkins_collected = clampi(int(progress.get("pumpkins_collected", 0)), 0, _pumpkin_requirement_for_current_level())
	rituals_completed = clampi(int(progress.get("rituals_completed", 0)), 0, total_rituals_required)
	absolute_ritual_relics_delivered = clampi(int(progress.get("relics_delivered", 0)), 0, total_absolute_ritual_relics)
	current_health = clampi(int(progress.get("health", current_health)), 1, max_health)
	var saved_position: Variant = progress.get("player_position", [])
	if saved_position is Array and saved_position.size() >= 3:
		global_position = Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))
		velocity = Vector3.ZERO
	var pumpkins_complete: bool = current_level_number < 3 or pumpkins_collected >= _pumpkin_requirement_for_current_level()
	var relics_complete: bool = current_level_number != 4 or absolute_ritual_relics_delivered >= total_absolute_ritual_relics
	exit_unlocked = rituals_completed >= total_rituals_required and pumpkins_complete and relics_complete
	if current_level_number == 4 and exit_unlocked:
		_purification_sequence_active = false
		_purification_sequence_finished = true
		controls_frozen = false
	update_health_ui()
	_update_ritual_counter_ui()
	if exit_unlocked:
		cemetery_exit_unlocked.emit()


func show_level_intro(level_number: int) -> void:
	if current_level_number != level_number or level_number < 1 or _level_2_intro_layer != null:
		return
	var manager := get_node("/root/GameManager")
	if bool(manager.get("skip_next_intro")):
		manager.set("skip_next_intro", false)
		_log("intro_skipped", {"source": "main_menu"})
		return
	get_tree().paused = true
	set_meta("level_2_intro_active", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	countdown_time = _countdown_duration_for_level(level_number)
	_level_2_intro_layer = intro_scenes[level_number - 1].instantiate() as CanvasLayer
	add_child(_level_2_intro_layer)
	_add_transition_skip_input(_level_2_intro_layer)
	_level_2_intro_countdown_label = _level_2_intro_layer.get_node("Level2Announcement/Content/Countdown") as Label
	_level_2_intro_timer = _level_2_intro_layer.get_node("Level2IntroCountdownTimer") as Timer
	_level_2_intro_countdown_label.text = "El juego comienza en: %d..." % countdown_time
	_level_2_intro_timer.timeout.connect(_on_level_2_intro_countdown)
	_level_2_intro_timer.start()
	_log("intro_shown")


func _countdown_duration_for_level(level_number: int) -> int:
	match level_number:
		1:
			return 5
		2:
			return 10
		3, 4:
			return 15
	return 10


func _finish_level_intro() -> void:
	if _level_2_intro_layer == null or not is_instance_valid(_level_2_intro_layer):
		return
	_log("intro_finished")
	if _level_2_intro_timer != null:
		_level_2_intro_timer.stop()
	_level_2_intro_layer.queue_free()
	_level_2_intro_layer = null
	_level_2_intro_timer = null
	_level_2_intro_countdown_label = null
	set_meta("level_2_intro_active", false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_level_2_intro_countdown() -> void:
	countdown_time -= 1
	if countdown_time <= 0:
		if is_instance_valid(_level_2_intro_countdown_label):
			_level_2_intro_countdown_label.text = "El juego comienza en: 0..."
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_level_2_intro_layer):
			return
		_finish_level_intro()
		return
	if is_instance_valid(_level_2_intro_countdown_label):
		_level_2_intro_countdown_label.text = "El juego comienza en: %d..." % countdown_time


func set_exit_gate_radar_target(target: Node3D, gate_is_open: bool = false) -> void:
	_radar_exit_gate_target = target
	_radar_exit_gate_open = gate_is_open
	_update_exit_gate_radar_marker()


func set_exit_gate_radar_open(gate_is_open: bool) -> void:
	_radar_exit_gate_open = gate_is_open
	_update_exit_gate_radar_marker()


func _refresh_ritual_shrines() -> void:
	var live_shrines: Array[RitualAltar] = []
	for altar in ritual_shrines:
		if is_instance_valid(altar):
			live_shrines.append(altar)
	ritual_shrines = live_shrines
	if ritual_shrines.size() >= total_rituals_required:
		return
	for node in get_tree().get_nodes_in_group("ritual_altars"):
		var altar := node as RitualAltar
		if altar != null and is_instance_valid(altar) and not ritual_shrines.has(altar):
			ritual_shrines.append(altar)
		if ritual_shrines.size() >= total_rituals_required:
			break


func _update_ritual_radar_markers() -> void:
	if camera == null or not is_instance_valid(camera):
		for marker in _radar_altar_markers:
			marker.visible = false
		return
	for index in _radar_altar_markers.size():
		var marker: Label = _radar_altar_markers[index]
		if index >= ritual_shrines.size():
			marker.visible = false
			continue
		var altar: RitualAltar = ritual_shrines[index]
		if altar == null or not is_instance_valid(altar):
			marker.visible = false
			continue
		var toward_altar: Vector3 = altar.global_position - global_position
		toward_altar.y = 0.0
		if toward_altar.length_squared() < 0.0001:
			marker.visible = false
			continue
		var radar_center: Vector2 = _radar_arrow_area.size * 0.5
		var marker_center: Vector2 = _world_to_radar_position(altar.global_position, radar_center)
		marker.position = marker_center - marker.size * 0.5
		marker.visible = true
		if altar.is_lit:
			marker.add_theme_color_override("font_color", Color(0.35, 1.0, 0.52, 0.78))
			marker.modulate.a = 0.62
		else:
			marker.add_theme_color_override("font_color", Color(ALTAR_MARKER_COLOR_HEX))
			marker.modulate.a = 1.0


func _update_exit_gate_radar_marker() -> void:
	if _radar_exit_gate_marker == null:
		return
	if not _radar_exit_gate_open or _radar_exit_gate_target == null or not is_instance_valid(_radar_exit_gate_target):
		_radar_exit_gate_marker.visible = false
		return
	if camera == null or not is_instance_valid(camera):
		_radar_exit_gate_marker.visible = false
		return
	var toward_gate: Vector3 = _radar_exit_gate_target.global_position - global_position
	toward_gate.y = 0.0
	if toward_gate.length_squared() < 0.0001:
		_radar_exit_gate_marker.visible = false
		return
	var radar_center: Vector2 = _radar_arrow_area.size * 0.5
	var marker_center: Vector2 = _world_to_radar_position(_radar_exit_gate_target.global_position, radar_center)
	_radar_exit_gate_marker.position = marker_center - _radar_exit_gate_marker.size * 0.5
	_radar_exit_gate_marker.visible = true
	_radar_exit_gate_marker.modulate.a = 1.0


func _radar_relative_angle(world_position: Vector3) -> float:
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	var toward_target: Vector3 = world_position - global_position
	toward_target.y = 0.0
	if forward.length_squared() < 0.0001 or toward_target.length_squared() < 0.0001:
		return 0.0
	forward = forward.normalized()
	toward_target = toward_target.normalized()
	var cross_y: float = forward.cross(toward_target).dot(Vector3.UP)
	return atan2(-cross_y, forward.dot(toward_target))


func _world_to_radar_position(world_position: Vector3, radar_center: Vector2) -> Vector2:
	var toward_target: Vector3 = world_position - global_position
	toward_target.y = 0.0
	var angle: float = _radar_relative_angle(world_position)
	var radar_radius: float = clampf(toward_target.length() / 30.0 * 50.0, 5.0, 50.0)
	return radar_center + Vector2(sin(angle), -cos(angle)) * radar_radius


func _update_radar_alert_state(delta: float) -> void:
	if _radar_alert_label == null:
		return
	var any_chasing: bool = false
	var any_investigating: bool = false
	for enemy_node in enemies:
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		var enemy_state: Variant = enemy_node.get("state")
		if enemy_state == null:
			continue
		any_chasing = any_chasing or int(enemy_state) == EnemyAI.State.CHASE
		any_investigating = any_investigating or int(enemy_state) == EnemyAI.State.INVESTIGATE
	if any_chasing:
		_radar_alert_flash_time += delta
		var pulse: float = 0.78 + 0.22 * (0.5 + 0.5 * sin(_radar_alert_flash_time * 7.0))
		_radar_alert_label.text = "ESTADO: ¡TE HA VISTO!"
		_radar_alert_settings.font_color = Color(1.0, 0.2, 0.2)
		_radar_alert_settings.shadow_color = Color(1.0, 0.2, 0.2, 0.72)
		_radar_alert_label.modulate.a = pulse
	elif any_investigating:
		_radar_alert_label.text = "ESTADO: INVESTIGANDO RUIDO"
		_radar_alert_settings.font_color = Color(1.0, 0.8, 0.2)
		_radar_alert_settings.shadow_color = Color(1.0, 0.8, 0.2, 0.58)
		_radar_alert_label.modulate.a = 1.0
	else:
		_radar_alert_label.text = "ESTADO: PATRULLANDO"
		_radar_alert_settings.font_color = Color(0.2, 0.9, 0.4)
		_radar_alert_settings.shadow_color = Color(0.2, 0.9, 0.4, 0.58)
		_radar_alert_label.modulate.a = 1.0
	_update_pursuit_music(any_chasing)


func _update_pursuit_music(is_chasing: bool) -> void:
	var level_root := get_parent()
	if level_root == null:
		return
	var level_music := level_root.get_node_or_null("LevelMusicPlayer") as AudioStreamPlayer
	var pursuit_music := level_root.get_node_or_null("PursuitMusicPlayer") as AudioStreamPlayer
	if pursuit_music == null:
		return
	if is_chasing:
		if not pursuit_music.playing:
			if level_music != null:
				level_music.stream_paused = true
			pursuit_music.play()
	elif pursuit_music.playing:
		pursuit_music.stop()
		if level_music != null:
			level_music.stream_paused = false
	elif level_music != null and level_music.stream_paused:
		level_music.stream_paused = false


func take_damage(amount: int = 1) -> void:
	if is_dead or is_hiding or _cover_transition_active or amount <= 0:
		return
	var previous_health := current_health
	current_health = maxi(0, current_health - amount)
	if current_health == previous_health:
		return
	add_screenshake(0.4)
	_regeneration_timer = regeneration_delay
	_log("damage_taken", {"amount": previous_health - current_health, "health": current_health})
	health_changed.emit(current_health, max_health)
	play_sound_effect(SFX_ENEMY_HIT)
	_play_damage_feedback()
	if current_health <= 0:
		_die()


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	var before_heal := current_health
	current_health = mini(current_health + amount, max_health)
	_log("health_restored", {"amount": current_health - before_heal, "health": current_health})
	_regeneration_timer = regeneration_delay if current_health < max_health else 0.0
	update_health_ui()


func update_health_ui() -> void:
	health_changed.emit(current_health, max_health)


func apply_knockback(impact_position: Vector3) -> void:
	if is_dead or is_hiding or _cover_transition_active:
		return
	var direction: Vector3 = global_position - impact_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = global_transform.basis.x
		direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	_knockback_velocity = direction.normalized() * knockback_strength
	_knockback_time_remaining = knockback_duration


func _play_damage_feedback() -> void:
	if _damage_flash_rect != null and is_instance_valid(_damage_flash_rect):
		if _damage_flash_tween != null and _damage_flash_tween.is_running():
			_damage_flash_tween.kill()
		_damage_flash_rect.color = Color(1.0, 0.0, 0.0, 0.0)
		_damage_flash_tween = create_tween()
		_damage_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var flash_peak: float = clampf(damage_flash_alpha, 0.2, 0.8)
		var flash_in: float = damage_feedback_duration * 0.3
		var flash_out: float = damage_feedback_duration - flash_in
		_damage_flash_tween.tween_property(_damage_flash_rect, "color:a", flash_peak, flash_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_damage_flash_tween.tween_property(_damage_flash_rect, "color:a", 0.0, flash_out).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_shake_camera()


func _shake_camera() -> void:
	if camera_shake == null:
		return
	if _camera_shake_tween != null and _camera_shake_tween.is_running():
		_camera_shake_tween.kill()
	_camera_shake_tween = create_tween()
	_camera_shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for _index in range(6):
		var shake_offset := Vector3(
			randf_range(-camera_shake_intensity, camera_shake_intensity),
			randf_range(-camera_shake_intensity * 0.65, camera_shake_intensity * 0.65),
			0.0
		)
		_camera_shake_tween.tween_property(camera_shake, "position", shake_offset, 0.025).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_shake_tween.tween_property(camera_shake, "position", Vector3.ZERO, 0.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _camera_rest_position() -> Vector3:
	var result := _camera_base_position
	var standing_height := _standing_camera_height * (0.5 if is_crouching else 1.0)
	var hidden_height := _standing_camera_height * minf(0.5 if is_crouching else 1.0, hiding_camera_height_ratio) - 0.08
	result.y = lerpf(standing_height, hidden_height, _hiding_camera_weight)
	result.z += 0.12 * _hiding_camera_weight
	return result


func _apply_camera_pose() -> void:
	# Independent authored offsets prevent animation, mouse look and hit feedback
	# from overwriting one another. None of these nodes moves the body collider.
	if camera == null or not is_instance_valid(camera):
		return
	var visual_position := hiding_motion.position if hiding_motion != null else Vector3.ZERO
	var visual_rotation := hiding_motion.rotation if hiding_motion != null else Vector3.ZERO
	var hit_offset := camera_shake.position if camera_shake != null else Vector3.ZERO
	var screenshake_offset := Vector3(_screenshake_offset.x, _screenshake_offset.y, 0.0)
	camera.position = _camera_rest_position() + visual_position + hit_offset + screenshake_offset + _head_bob_offset
	camera.rotation = Vector3(_pitch, _camera_base_rotation.y, _camera_base_rotation.z + _head_bob_roll) + visual_rotation


func _on_hiding_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"hide_enter" and is_hiding:
		hiding_animation.play("hide_hold", 0.08)
	elif animation_name == &"hide_exit" and not is_hiding:
		if _hiding_overlay_layer != null:
			_hiding_overlay_layer.visible = false
	_apply_camera_pose()


func _die() -> void:
	if is_dead:
		return
	get_node("/root/GameManager").apply_penalty()
	get_node("/root/LevelManager").call("stop_level_timer")
	get_node("/root/LevelManager").call("refresh_time_score_hud")
	is_dead = true
	_log("player_died", {"health": current_health})
	play_sound_effect(SFX_LOSE, true)
	freeze_controls()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_died.emit()


func _add_transition_skip_input(parent: Node) -> void:
	var skip_input := parent.get_node_or_null("TransitionSkipInput")
	if skip_input != null:
		skip_input.connect("skip_requested", _on_transition_skip_requested)


func _on_transition_skip_requested() -> void:
	if _level_2_intro_layer != null and is_instance_valid(_level_2_intro_layer):
		_log("intro_skipped", {"source": "button_or_enter"})
		_finish_level_intro()


func _unhandled_input(event: InputEvent) -> void:
	if controls_frozen or _cover_transition_active:
		return
	if event is InputEventMouseMotion and camera != null:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		_apply_camera_pose()
	if event.is_action_pressed("ritual_interact"):
		_try_light_nearby_altar()
	if event.is_action_pressed("absolute_ritual_interact"):
		_try_interact_absolute_ritual_relic()
	if event.is_action_pressed("health_skull_interact"):
		_try_collect_nearby_health_skull()
	if event.is_action_pressed("hide_interact"):
		if is_hiding:
			play_sound_effect(SFX_HIDE)
			_set_hiding(false, null, true)
		else:
			_interact_with_target()
	if event.is_action_pressed("interact"):
		if current_level_number >= 3 and _try_collect_nearby_pumpkin():
			return
		_interact_with_collectible_target()


func _try_collect_nearby_pumpkin() -> bool:
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("try_collect_nearby_pumpkin"):
		return false
	return bool(level_builder.call("try_collect_nearby_pumpkin", self))


func _try_collect_nearby_health_skull() -> bool:
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("try_collect_nearby_health_skull"):
		return false
	return bool(level_builder.call("try_collect_nearby_health_skull", self))


func _try_interact_absolute_ritual_relic() -> bool:
	if current_level_number != 4:
		return false
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("try_interact_absolute_ritual_relic"):
		return false
	var interacted: bool = bool(level_builder.call("try_interact_absolute_ritual_relic", self))
	if interacted:
		play_sound_effect(SFX_HEALTH_SKULL_PICKUP, false, 0.65)
		_persist_campaign_level_progress()
	return interacted


func carry_absolute_ritual_relic(relic: Node3D) -> bool:
	return _carry_absolute_ritual_relic(relic, true)


func restore_carried_absolute_ritual_relic(relic: Node3D) -> bool:
	return _carry_absolute_ritual_relic(relic, false)


func _carry_absolute_ritual_relic(relic: Node3D, record_pickup: bool) -> bool:
	if current_level_number != 4 or is_carrying_absolute_ritual_relic or relic == null:
		return false
	var carry_anchor := get_node_or_null("AbsoluteRitualCarryAnchor") as Node3D
	if carry_anchor == null:
		return false
	relic.reparent(carry_anchor)
	relic.position = Vector3(0.18, -0.22, 0.0)
	relic.rotation = Vector3.ZERO
	carried_absolute_ritual_relic = relic
	is_carrying_absolute_ritual_relic = true
	if record_pickup:
		_log("relic_picked_up", {"object": str(relic.name)})
	is_running = false
	_update_crouch_state(false)
	_set_carried_relic_visible(not is_hidden)
	return true


func release_absolute_ritual_relic() -> Node3D:
	if not is_carrying_absolute_ritual_relic:
		return null
	var relic := carried_absolute_ritual_relic
	_log("relic_released", {"object": str(relic.name) if is_instance_valid(relic) else ""})
	if relic != null and is_instance_valid(relic):
		_set_visual_tree_visible(relic.get_node_or_null("RelicVisual"), true)
	carried_absolute_ritual_relic = null
	is_carrying_absolute_ritual_relic = false
	_update_crouch_state(Input.is_action_pressed("crouch"))
	return relic


func set_absolute_ritual_relic_progress(delivered: int, required: int) -> void:
	total_absolute_ritual_relics = maxi(0, required)
	absolute_ritual_relics_delivered = clampi(delivered, 0, total_absolute_ritual_relics)
	_update_ritual_counter_ui()
	_persist_campaign_level_progress()


func _interact_with_collectible_target() -> void:
	if interaction_ray == null or not interaction_ray.is_colliding():
		return
	var target := interaction_ray.get_collider()
	if target != null and target.has_method("interact"):
		target.interact(self)


func collect_pumpkin() -> void:
	if current_level_number < 3 or pumpkins_collected >= _pumpkin_requirement_for_current_level():
		return
	pumpkins_collected += 1
	_log("pumpkin_collected", {"collected": pumpkins_collected, "required": _pumpkin_requirement_for_current_level()})
	if pumpkins_collected == _pumpkin_requirement_for_current_level():
		_log("mission_completed", {"mission": "pumpkins"})
	play_sound_effect(SFX_PUMPKIN)
	_update_ritual_counter_ui()
	_persist_campaign_level_progress()


func _pumpkin_requirement_for_current_level() -> int:
	return FINAL_LEVEL_PUMPKINS_REQUIRED if current_level_number >= 4 else PUMPKINS_REQUIRED


func _show_pumpkin_lock_message() -> void:
	if _pumpkin_lock_message == null or _pumpkin_lock_timer == null:
		return
	_pumpkin_lock_message.visible = true
	_pumpkin_lock_timer.start()


func _hide_pumpkin_lock_message() -> void:
	if _pumpkin_lock_message != null:
		_pumpkin_lock_message.visible = false


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = jump_buffer_time
	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	if controls_frozen:
		_update_head_bob(delta, false)
		_update_footstep_audio(false)
		velocity = Vector3.ZERO
		return
	if _cover_transition_active:
		_update_head_bob(delta, false)
		_update_footstep_audio(false)
		velocity = Vector3.ZERO
		return
	var wants_to_crouch: bool = Input.is_action_pressed("crouch")
	if is_carrying_absolute_ritual_relic:
		wants_to_crouch = false
	_update_crouch_state(wants_to_crouch)

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if is_hiding:
		if input_vector.length_squared() > 0.01:
			_set_hiding(false, null, true)
			_update_footstep_audio(false)
			velocity = Vector3.ZERO
			return
		velocity = Vector3.ZERO
		_update_head_bob(delta, false)
		_update_footstep_audio(false)
		_update_noise(delta, false)
		return
	var forward_strength := maxf(-input_vector.y, 0.0)
	var backward_strength := maxf(input_vector.y, 0.0)
	var move_direction := transform.basis.x * input_vector.x
	move_direction += -transform.basis.z * forward_strength
	move_direction += transform.basis.z * backward_strength
	move_direction = move_direction.normalized()
	var has_movement_input: bool = input_vector.length_squared() > 0.0
	var sprint_requested: bool = Input.is_action_pressed("sprint")
	var can_sprint_while_carrying: bool = is_carrying_absolute_ritual_relic and _is_any_enemy_chasing()
	var can_sprint: bool = can_sprint_while_carrying if is_carrying_absolute_ritual_relic else not is_crouching
	var was_running := is_running
	is_running = has_movement_input and sprint_requested and can_sprint
	if was_running != is_running:
		_log("sprint_started" if is_running else "sprint_ended")
	var current_speed: float = walk_speed
	if is_carrying_absolute_ritual_relic:
		# Carrying remains slower than standing, but is a little faster than crouch.
		current_speed = sprint_speed if is_running else walk_speed * 0.7
	elif is_crouching:
		current_speed = walk_speed * 0.5
	elif is_running:
		current_speed = sprint_speed
	velocity.x = move_direction.x * current_speed
	velocity.z = move_direction.z * current_speed
	if _knockback_time_remaining > 0.0:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		var knockback_decay: float = knockback_strength / maxf(knockback_duration, 0.01)
		_knockback_velocity.x = move_toward(_knockback_velocity.x, 0.0, knockback_decay * delta)
		_knockback_velocity.z = move_toward(_knockback_velocity.z, 0.0, knockback_decay * delta)
		_knockback_time_remaining = maxf(0.0, _knockback_time_remaining - delta)

	var can_jump_while_carrying: bool = is_carrying_absolute_ritual_relic
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and not is_hiding and (not is_crouching or can_jump_while_carrying):
		velocity.y = jump_velocity
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		_log("jumped")
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	var was_on_floor: bool = is_on_floor()
	move_and_slide()
	_update_head_bob(delta, true)
	var landed: bool = not was_on_floor and is_on_floor()
	if landed:
		add_screenshake(0.15)
	var horizontal_motion: bool = absf(velocity.x) > 0.01 or absf(velocity.z) > 0.01
	if is_on_floor() and horizontal_motion:
		add_screenshake(0.03 if is_running else 0.01)
	_update_footstep_audio(is_on_floor() and horizontal_motion and is_running)
	_update_noise(delta, input_vector.length_squared() > 0.0)


func _update_footstep_audio(should_play: bool) -> void:
	if walk_audio_player == null or not is_instance_valid(walk_audio_player):
		return
	if should_play:
		if not walk_audio_player.playing:
			walk_audio_player.play()
	elif walk_audio_player.playing:
		walk_audio_player.stop()


func play_sound_effect(stream: AudioStream, process_always: bool = false, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	var audio_player := sound_effect_scene.instantiate() as AudioStreamPlayer
	audio_player.stream = stream
	audio_player.pitch_scale = maxf(pitch_scale, 0.01)
	audio_player.process_mode = Node.PROCESS_MODE_ALWAYS if process_always else Node.PROCESS_MODE_INHERIT
	var audio_parent: Node = get_tree().root if process_always else self
	audio_parent.add_child(audio_player)
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()


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
	var cover := _get_hiding_cover_target()
	if cover != null:
		_set_hiding(true, cover)
		return
	if interaction_ray == null or not interaction_ray.is_colliding():
		return
	var target := interaction_ray.get_collider()
	if target != null and target.has_method("interact"):
		target.interact(self)


func _configure_hiding_ray() -> void:
	if camera == null:
		return
	if hiding_ray == null:
		hiding_ray = camera.get_node_or_null("HidingRay") as RayCast3D
	if hiding_ray != null:
		hiding_detection_distance = hiding_ray.target_position.length()
		hiding_ray.add_exception(self)


func _get_hiding_cover_target() -> Node3D:
	if hiding_ray == null or not is_instance_valid(hiding_ray) or not hiding_ray.is_inside_tree():
		return null
	hiding_ray.force_raycast_update()
	if not hiding_ray.is_colliding():
		return null
	var candidate := hiding_ray.get_collider() as Node
	while candidate != null:
		if candidate.is_in_group("hide_objects") and candidate is Node3D:
			_hiding_collision_point = hiding_ray.get_collision_point()
			_hiding_collision_normal = hiding_ray.get_collision_normal()
			return candidate as Node3D
		candidate = candidate.get_parent()
	return null


func _is_leaf_tree_cover(target: Node3D) -> bool:
	var candidate: Node = target
	while candidate != null:
		if candidate.is_in_group("leaf_trees"):
			return true
		candidate = candidate.get_parent()
	return false


func _update_interaction_prompt() -> void:
	if _interaction_prompt == null:
		return
	if _has_escaped:
		_interaction_prompt.visible = false
		return
	var level_builder := get_parent()
	if current_level_number == 4 and level_builder != null and level_builder.has_method("get_absolute_ritual_interaction_prompt"):
		var relic_prompt: String = str(level_builder.call("get_absolute_ritual_interaction_prompt", self))
		if not relic_prompt.is_empty():
			_interaction_prompt.text = relic_prompt
			_interaction_prompt.visible = true
			return
	if _exit_gate_nearby:
		if can_escape_cemetery():
			_interaction_prompt.text = "[SALIDA ABIERTA] Cruza el portón verde"
		else:
			_interaction_prompt.text = "[BLOQUEADO] Enciende los 4 rituales para abrir la salida"
		_interaction_prompt.visible = true
		return
	if is_hiding:
		_interaction_prompt.text = "[E] Salir de cobertura"
		_interaction_prompt.visible = true
		return
	var altar := _get_nearby_ritual_altar()
	if altar != null:
		if current_level_number == 4 and pumpkins_collected >= _pumpkin_requirement_for_current_level() and absolute_ritual_relics_delivered < total_absolute_ritual_relics:
			_interaction_prompt.text = "[BLOQUEADO] Lleva los 2 restos frente al portón"
		elif current_level_number >= 3 and pumpkins_collected < _pumpkin_requirement_for_current_level():
			_interaction_prompt.text = "[BLOQUEADO] Reúne las %d calabazas" % _pumpkin_requirement_for_current_level()
		else:
			_interaction_prompt.text = "[Q] Encender ritual"
		_interaction_prompt.visible = true
		return
	if current_level_number >= 3 and level_builder != null and level_builder.has_method("get_nearby_pumpkin"):
		if level_builder.call("get_nearby_pumpkin", self, 2.0) != null:
			_interaction_prompt.text = "[F] Recoger calabaza"
			_interaction_prompt.visible = true
			return
	if current_level_number >= 2 and level_builder != null and level_builder.has_method("get_nearby_health_skull"):
		if level_builder.call("get_nearby_health_skull", self, 2.0) != null:
			_interaction_prompt.text = "[R] Recoger cráneo curativo"
			_interaction_prompt.visible = true
			return
	_hiding_target = _get_hiding_cover_target()
	_interaction_prompt.text = "[E] Esconderse detrás del objeto"
	_interaction_prompt.visible = _hiding_target != null


func _get_nearby_ritual_altar() -> RitualAltar:
	if rituals_completed >= total_rituals_required:
		return null
	var facing := -camera.global_transform.basis.z if camera != null else -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return null
	facing = facing.normalized()
	var best_altar: RitualAltar
	var best_distance_squared: float = ritual_interaction_distance * ritual_interaction_distance
	for node in get_tree().get_nodes_in_group("ritual_altars"):
		var altar := node as RitualAltar
		if altar == null or not is_instance_valid(altar) or altar.is_lit:
			continue
		if not altar.is_player_nearby(self):
			continue
		var to_altar := altar.global_position - global_position
		to_altar.y = 0.0
		var distance_squared: float = to_altar.length_squared()
		if distance_squared > best_distance_squared or distance_squared < 0.0001:
			continue
		if facing.dot(to_altar.normalized()) < 0.2:
			continue
		best_altar = altar
		best_distance_squared = distance_squared
	return best_altar


func _try_light_nearby_altar() -> void:
	var altar := _get_nearby_ritual_altar()
	if altar == null:
		return
	if current_level_number >= 3 and pumpkins_collected < _pumpkin_requirement_for_current_level():
		_pumpkin_lock_message.text = "¡Debes recolectar %d calabazas antes de realizar los rituales!" % _pumpkin_requirement_for_current_level()
		_show_pumpkin_lock_message()
		return
	if current_level_number == 4 and absolute_ritual_relics_delivered < total_absolute_ritual_relics:
		_pumpkin_lock_message.text = "Construye el ritual absoluto: lleva los 2 restos frente al portón."
		_show_pumpkin_lock_message()
		return
	if not altar.activate():
		return
	rituals_completed = mini(rituals_completed + 1, total_rituals_required)
	_log("altar_activated", {"object": str(altar.name), "completed": rituals_completed, "required": total_rituals_required})
	ritual_progress_changed.emit(rituals_completed, total_rituals_required)
	_update_ritual_counter_ui()
	noise_emitted.emit(altar.global_position, 1.0)
	if rituals_completed >= total_rituals_required:
		_log("mission_completed", {"mission": "altars"})
		play_sound_effect(SFX_EXIT_UNLOCK)
		exit_unlocked = true
		if current_level_number == 4:
			_start_final_purification_sequence()
		else:
			_update_ritual_counter_ui()
			cemetery_exit_unlocked.emit()
	_persist_campaign_level_progress()


func _start_final_purification_sequence() -> void:
	if _purification_sequence_active or _purification_sequence_finished:
		return
	_purification_sequence_active = true
	controls_frozen = true
	velocity = Vector3.ZERO
	_purify_level_enemies()
	_update_ritual_counter_ui()
	# Notify the builder immediately so the gate opens during the purification effect.
	cemetery_exit_unlocked.emit()
	call_deferred("_run_final_purification_sequence")


func _purify_level_enemies() -> void:
	var enemies_to_purify: Array[Node3D] = []
	for enemy_node in enemies:
		if enemy_node != null and is_instance_valid(enemy_node) and not enemies_to_purify.has(enemy_node):
			enemies_to_purify.append(enemy_node)
	for node in get_tree().get_nodes_in_group("enemy"):
		var group_enemy := node as Node3D
		if group_enemy != null and is_instance_valid(group_enemy) and not enemies_to_purify.has(group_enemy):
			enemies_to_purify.append(group_enemy)
	for enemy_node in enemies_to_purify:
		enemy_node.remove_from_group("enemy")
		enemy_node.visible = false
		enemy_node.set_process(false)
		enemy_node.set_physics_process(false)
		if enemy_node is CollisionObject3D:
			var collision_object := enemy_node as CollisionObject3D
			collision_object.collision_layer = 0
			collision_object.collision_mask = 0
		enemy_node.queue_free()
	enemies.clear()


func _run_final_purification_sequence() -> void:
	var shake_tween := _create_purification_camera_shake(1.8)
	await _fade_purification_flash_to(1.0, 1.0)
	# Hold the full white frame until the 1.8 second shake has finished.
	await get_tree().create_timer(0.8, true, false, true).timeout
	await _fade_purification_flash_to(0.0, 1.0)
	if shake_tween != null and shake_tween.is_running():
		await shake_tween.finished
	_purification_sequence_finished = true
	_purification_sequence_active = false
	controls_frozen = false
	update_objective_ui()


func _create_purification_camera_shake(duration: float) -> Tween:
	if camera == null or not is_instance_valid(camera):
		return null
	if _camera_shake_tween != null and _camera_shake_tween.is_running():
		_camera_shake_tween.kill()
	if camera_shake == null:
		return null
	var shake_tween := create_tween()
	shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var segment_count: int = maxi(1, ceili(duration / 0.06))
	var segment_duration: float = duration / float(segment_count)
	for _segment in range(segment_count):
		var offset := Vector3(
			randf_range(-0.045, 0.045),
			randf_range(-0.035, 0.035),
			0.0
		)
		shake_tween.tween_property(camera_shake, "position", offset, segment_duration)
	shake_tween.tween_property(camera_shake, "position", Vector3.ZERO, 0.08)
	_camera_shake_tween = shake_tween
	return shake_tween


func _fade_purification_flash_to(target_alpha: float, duration: float) -> void:
	if _purification_flash_rect == null or not is_instance_valid(_purification_flash_rect):
		return
	if _purification_flash_tween != null and _purification_flash_tween.is_running():
		_purification_flash_tween.kill()
	_purification_flash_rect.visible = true
	_purification_flash_tween = create_tween()
	_purification_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_purification_flash_tween.tween_property(_purification_flash_rect, "color:a", clampf(target_alpha, 0.0, 1.0), duration)
	await _purification_flash_tween.finished


func _update_ritual_counter_ui() -> void:
	update_objective_ui()


func update_objective_ui() -> void:
	if _objective_container == null:
		return
	var altars_complete: bool = rituals_completed >= total_rituals_required
	var pumpkin_requirement: int = _pumpkin_requirement_for_current_level()
	var pumpkins_complete: bool = current_level_number < 3 or pumpkins_collected >= pumpkin_requirement
	var absolute_relics_complete: bool = current_level_number != 4 or absolute_ritual_relics_delivered >= total_absolute_ritual_relics
	var objectives_complete: bool = (
		exit_unlocked
		and altars_complete
		and pumpkins_complete
		and absolute_relics_complete
		and (current_level_number != 4 or _purification_sequence_finished)
	)
	if _ritual_counter_label != null:
		_ritual_counter_label.visible = false
		if exit_unlocked:
			_ritual_counter_label.text = "PORTÓN PRINCIPAL ABIERTO, ESCAPA!!!"
			_ritual_counter_label.label_settings.font_color = Color(0.282, 1.0, 0.384, 1.0)
		else:
			_ritual_counter_label.text = "Rituales completados: %d / %d" % [rituals_completed, total_rituals_required]
			_ritual_counter_label.label_settings.font_color = Color(1.0, 0.78, 0.42, 0.98)

	if _ritual_mission_label != null:
		_ritual_mission_label.visible = true
		if current_level_number <= 2:
			_ritual_mission_label.text = "Enciende los altares"
			var altar_title_color: Color = Color(1.0, 0.78, 0.42, 1.0)
			if altars_complete:
				altar_title_color = Color(0.282, 1.0, 0.384, 1.0)
			_ritual_mission_label.add_theme_color_override("default_color", altar_title_color)
		else:
			if current_level_number == 4:
				_ritual_mission_label.text = "Reúne las %d calabazas para desbloquear los restos" % pumpkin_requirement
			else:
				_ritual_mission_label.text = "Reúne las %d calabazas para desbloquear los altares" % pumpkin_requirement
			var pumpkin_title_color: Color = Color(1.0, 0.78, 0.42, 1.0)
			if pumpkins_complete:
				pumpkin_title_color = Color(0.282, 1.0, 0.384, 1.0)
			_ritual_mission_label.add_theme_color_override("default_color", pumpkin_title_color)

	if _altar_mission_title_label != null:
		_altar_mission_title_label.visible = current_level_number >= 3 and pumpkins_complete and absolute_relics_complete
		_altar_mission_title_label.text = "Enciende los altares"
		var altar_phase_title_color: Color = Color(1.0, 0.78, 0.42, 1.0)
		if altars_complete:
			altar_phase_title_color = Color(0.282, 1.0, 0.384, 1.0)
		_altar_mission_title_label.add_theme_color_override("default_color", altar_phase_title_color)

	if _absolute_ritual_title_label != null:
		_absolute_ritual_title_label.visible = current_level_number == 4 and pumpkins_complete
		_absolute_ritual_title_label.text = "Construye el ritual absoluto"
		var relic_title_color: Color = Color(1.0, 0.78, 0.42, 1.0)
		if absolute_relics_complete:
			relic_title_color = Color(0.282, 1.0, 0.384, 1.0)
		_absolute_ritual_title_label.add_theme_color_override("default_color", relic_title_color)

	if _absolute_ritual_progress_label != null:
		_absolute_ritual_progress_label.text = "Lleva los restos ([color=%s]t[/color]) al punto ([color=%s]#[/color]): %d / %d" % [ABSOLUTE_RELIC_MARKER_COLOR_HEX, RITUAL_DELIVERY_MARKER_COLOR_HEX, absolute_ritual_relics_delivered, total_absolute_ritual_relics]
		_absolute_ritual_progress_label.visible = current_level_number == 4 and pumpkins_complete and not absolute_relics_complete
		_absolute_ritual_progress_label.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8, 1.0))

	if _pumpkin_counter_label != null:
		_pumpkin_counter_label.visible = current_level_number >= 3 and not pumpkins_complete
		_pumpkin_counter_label.text = "Calabazas ([color=%s]●[/color]) recolectadas: %d / %d" % [PUMPKIN_MARKER_COLOR_HEX, pumpkins_collected, pumpkin_requirement]
		_pumpkin_counter_label.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8, 1.0))

	if _altar_progress_label != null:
		_altar_progress_label.text = "Altares ([color=%s]◆[/color]) encendidos: %d / %d" % [ALTAR_MARKER_COLOR_HEX, rituals_completed, total_rituals_required]
		var altar_phase_active: bool = current_level_number <= 2 or (current_level_number >= 3 and pumpkins_complete and absolute_relics_complete)
		_altar_progress_label.visible = altar_phase_active and not altars_complete
		var altar_progress_color: Color = Color(0.8, 0.8, 0.8, 1.0)
		if altars_complete:
			altar_progress_color = Color(0.282, 1.0, 0.384, 1.0)
		_altar_progress_label.add_theme_color_override("default_color", altar_progress_color)

	if _healing_mission_label != null:
		_healing_mission_label.text = "Encuentra cráneos ([color=%s]■[/color]) para curarte" % SKULL_MARKER_COLOR_HEX
		_healing_mission_label.visible = current_level_number == 2
		_healing_mission_label.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8, 1.0))

	if _escape_mission_title_label != null:
		_escape_mission_title_label.text = "¡Escapa del cementerio!"
		_escape_mission_title_label.visible = objectives_complete
		_escape_mission_title_label.add_theme_color_override("default_color", Color(1.0, 0.78, 0.42, 1.0))

	if _escape_mission_label != null:
		if current_level_number == 4 and _purification_sequence_finished:
			_escape_mission_label.text = "Sigue el portón ([color=%s]■[/color]) para salir" % EXIT_GATE_MARKER_COLOR_HEX
		else:
			_escape_mission_label.text = "Sigue el ([color=%s]■[/color]) para salir" % EXIT_GATE_MARKER_COLOR_HEX
		_escape_mission_label.visible = objectives_complete
		var escape_instruction_color: Color = Color(0.8, 0.8, 0.8, 1.0)
		if _has_escaped and current_level_number < 4:
			escape_instruction_color = Color(0.282, 1.0, 0.384, 1.0)
		_escape_mission_label.add_theme_color_override("default_color", escape_instruction_color)

	# Reafirma el orden de la misión, con la instrucción de salida al final.
	var ordered_objectives: Array[Control] = []
	if current_level_number <= 2:
		ordered_objectives.append(_ritual_mission_label)
		ordered_objectives.append(_altar_progress_label)
		ordered_objectives.append(_healing_mission_label)
		ordered_objectives.append(_escape_mission_title_label)
		ordered_objectives.append(_escape_mission_label)
		ordered_objectives.append(_ritual_counter_label)
		ordered_objectives.append(_pumpkin_counter_label)
	else:
		ordered_objectives.append(_ritual_mission_label)
		ordered_objectives.append(_pumpkin_counter_label)
		ordered_objectives.append(_absolute_ritual_title_label)
		ordered_objectives.append(_absolute_ritual_progress_label)
		ordered_objectives.append(_altar_mission_title_label)
		ordered_objectives.append(_altar_progress_label)
		ordered_objectives.append(_escape_mission_title_label)
		ordered_objectives.append(_escape_mission_label)
		ordered_objectives.append(_ritual_counter_label)
	for index in range(ordered_objectives.size()):
		var objective: Control = ordered_objectives[index]
		if objective != null and objective.get_parent() == _objective_container:
			_objective_container.move_child(objective, index)


func can_escape_cemetery() -> bool:
	return exit_unlocked and rituals_completed >= total_rituals_required


func set_exit_gate_nearby(nearby: bool) -> void:
	_exit_gate_nearby = nearby
	_update_interaction_prompt()


func escape_cemetery() -> void:
	if _has_escaped or not can_escape_cemetery():
		return
	_has_escaped = true
	_log("level_completed", {"seconds_left": int(get_node("/root/LevelManager").get("seconds_left"))})
	_level_score_seconds = int(get_node("/root/LevelManager").get("seconds_left"))
	_level_score_points = _level_score_seconds
	get_node("/root/GameManager").add_level_score(_level_score_points)
	get_node("/root/LevelManager").call("stop_level_timer")
	get_node("/root/LevelManager").call("refresh_time_score_hud")
	update_objective_ui()
	freeze_controls()
	if _interaction_prompt != null:
		_interaction_prompt.visible = false
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		if enemy_node.has_method("freeze_for_escape"):
			enemy_node.call("freeze_for_escape")
	if current_level_number < 4:
		_show_level_complete_screen()
	else:
		_show_final_victory_screen()


func _show_level_complete_screen() -> void:
	var title_text: String
	var description_text: String
	match current_level_number:
		1:
			title_text = "¡HAS ESCAPADO DEL CEMENTERIO OLVIDADO!"
			description_text = "Lograste encender los primeros altares y escapar de las sombras."
		2:
			title_text = "¡SOBREVIVISTE A LA PESADILLA DE MEDIANOCHE!"
			description_text = "La luz de los craneos y altares te guió a través de la oscuridad."
		_:
			title_text = "¡COSECHA Y SACRIFICIO COMPLETADOS!"
			description_text = "Las calabazas malditas han sido arrancadas de raíz y el portón se ha abierto."
	_show_escape_screen(title_text, description_text, true)


func _show_final_victory_screen() -> void:
	var game_manager := get_node("/root/GameManager")
	_is_new_high_score = bool(game_manager.call("check_and_update_high_score"))
	_log("campaign_completed", {
		"final_score": int(game_manager.get("total_score")),
		"deaths": int(game_manager.get("penalties_count")),
		"penalty_points": int(game_manager.call("get_total_penalty_points")),
		"levels_completed": 4,
	})
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.call("end_session", "victory")
	if int(game_manager.get("active_save_slot")) > 0:
		var snapshot: Dictionary = game_manager.call("make_campaign_snapshot", 4, true)
		get_node("/root/CloudAccount").call("queue_checkpoint", 4, snapshot)
	_show_escape_screen(
		"¡EL RITUAL ABSOLUTO SE HA CUMPLIDO!",
		"Has profanado las tumbas, desafiado al enjambre y escapado con vida.",
		false
	)


func _show_escape_screen(title_text: String, description_text: String, show_continue: bool) -> void:
	if _victory_screen_layer != null:
		return
	_victory_screen_layer = (level_complete_scene if show_continue else victory_scene).instantiate() as CanvasLayer
	add_child(_victory_screen_layer)
	var layout := _victory_screen_layer.get_node("EscapeTransitionScreen/EscapePanel/Content")
	layout.get_node("EscapeTitle").text = title_text
	layout.get_node("EscapeDescription").text = description_text
	if show_continue:
		layout.get_node("Summary1").text = "Tiempo restante: %d seg" % _level_score_seconds
		layout.get_node("Summary2").text = "Puntos ganados: +%d" % _level_score_points
		layout.get_node("Summary3").text = "Puntuación Total: %d" % get_node("/root/GameManager").get("total_score")
		layout.get_node("ContinueButton").text = "CONTINUAR AL NIVEL %d" % (current_level_number + 1)
		layout.get_node("ContinueButton").pressed.connect(_play_menu_click)
		layout.get_node("ContinueButton").pressed.connect(_continue_to_next_level)
	else:
		var game_manager := get_node("/root/GameManager")
		var deaths: int = int(game_manager.get("penalties_count"))
		layout.get_node("Summary1").text = "%d %s: -%d puntos" % [deaths, "muerte total" if deaths == 1 else "muertes totales", int(game_manager.call("get_total_penalty_points"))]
		layout.get_node("Summary2").text = "Puntos ganados: +%d" % _level_score_points
		layout.get_node("Summary3").text = "PUNTUACIÓN TOTAL: %d pts" % game_manager.get("total_score")
		layout.get_node("HighScoreNotice").visible = _is_new_high_score
	layout.get_node("MenuButton").pressed.connect(_play_menu_click)
	layout.get_node("MenuButton").pressed.connect(_return_to_main_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _play_menu_click() -> void:
	play_sound_effect(SFX_MENU_CLICK, true)


func _continue_to_next_level() -> void:
	var next_level := current_level_number + 1
	var game_manager := get_node("/root/GameManager")
	var save_slot := int(game_manager.get("active_save_slot"))
	if save_slot > 0:
		var continue_button := _victory_screen_layer.get_node("EscapeTransitionScreen/EscapePanel/Content/ContinueButton") as Button
		continue_button.disabled = true
		continue_button.text = "GUARDANDO…"
		var snapshot: Dictionary = game_manager.call("make_campaign_snapshot", next_level, false)
		var account := get_node("/root/CloudAccount") as CloudAccountManager
		var save_result: Dictionary = await account.save_checkpoint(next_level, snapshot)
		if not save_result.get("ok", false):
			continue_button.disabled = false
			continue_button.text = "REINTENTAR GUARDADO"
			push_warning(str(save_result.get("error", "No se pudo guardar el progreso.")))
			return
	get_tree().paused = false
	var next_level_path := "res://scenes/Level_%02d.tscn" % next_level
	var error := get_tree().change_scene_to_file(next_level_path)
	if error != OK:
		push_error("No se pudo cargar el Nivel %d (error %d)." % [next_level, error])
func _return_to_main_menu() -> void:
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.call("end_session", "returned_to_menu")
	get_tree().paused = false
	get_node("/root/GameManager").call("reset_run")
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _set_hiding(hiding: bool, target: Node3D = null, restore_position: bool = false) -> void:
	if hiding:
		if is_hiding:
			return
		if target == null:
			target = _get_hiding_cover_target()
		if target == null or not is_on_floor():
			return
		_has_pre_hiding_transform = true
		_exiting_cover.clear()
		is_hiding = true
		var player_collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
		if player_collision != null:
			_hiding_collision_was_disabled = player_collision.disabled
			player_collision.disabled = true
		is_running = false
		_hiding_target = target
		current_cover_type = "leaf_tree" if _is_leaf_tree_cover(target) else "object"
		is_hidden = _hidden_by_zone or is_hiding
		_breath_time_remaining = 5.0
		if _hiding_overlay_layer != null:
			_hiding_overlay_layer.visible = true
		if breath_label != null:
			breath_label.text = "Aguantando la respiración  5..."
			breath_label.visible = true
		_update_crouch_state(is_crouching)
		if not _move_into_cover():
			is_hiding = false
			current_cover_type = ""
			_hiding_target = null
			is_hidden = _hidden_by_zone
			_restore_hiding_collision()
			if _hiding_overlay_layer != null:
				_hiding_overlay_layer.visible = false
			if breath_label != null:
				breath_label.visible = false
			_has_pre_hiding_transform = false
			_update_crouch_state(is_crouching)
		else:
			_log("hide_started", _hiding_state_payload())
			if hiding_animation != null:
				hiding_animation.play("hide_enter", 0.08)
			play_sound_effect(SFX_HIDE)
	else:
		if not is_hiding:
			return
		_exiting_cover = {"cover": str(_hiding_target.name) if is_instance_valid(_hiding_target) else "", "cover_type": current_cover_type}
		if hiding_animation != null:
			hiding_animation.play("hide_exit", 0.1)
		_cancel_cover_transition()
		is_hiding = false
		if hiding_animation == null and _hiding_overlay_layer != null:
			_hiding_overlay_layer.visible = false
		if breath_label != null:
			breath_label.visible = false
		current_cover_type = ""
		_hiding_target = null
		if restore_position and _has_pre_hiding_transform:
			_restore_from_cover()
		else:
			is_hidden = _hidden_by_zone
			_restore_hiding_collision()
			_update_crouch_state(is_crouching)
			_tween_hiding_camera(false)
			_has_pre_hiding_transform = false
		var ended_state := _hiding_state_payload()
		ended_state.merge(_exiting_cover, true)
		ended_state["breath_remaining"] = _breath_time_remaining
		_log("hide_ended", ended_state)
		if not _cover_transition_active:
			_exiting_cover.clear()
	_set_carried_relic_visible(not is_hidden)
	if _interaction_prompt != null:
		_update_interaction_prompt()


func _restore_hiding_collision() -> void:
	var player_collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if player_collision != null:
		player_collision.disabled = _hiding_collision_was_disabled
	_hiding_collision_was_disabled = false


func _tween_hiding_camera(entering: bool, duration: float = 0.2) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	if _hiding_camera_tween != null and _hiding_camera_tween.is_running():
		_hiding_camera_tween.kill()
	# Tween a stance weight, never the camera itself. A change of direction starts
	# at its current weight, so exiting midway through entry cannot snap the view.
	_hiding_camera_tween = create_tween()
	_hiding_camera_tween.tween_property(self, "_hiding_camera_weight", 1.0 if entering else 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _is_any_enemy_chasing() -> bool:
	for enemy_node in enemies:
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		var enemy_state: Variant = enemy_node.get("state")
		if enemy_state != null and int(enemy_state) == EnemyAI.State.CHASE:
			return true
	return false


func _set_carried_relic_visible(should_be_visible: bool) -> void:
	if carried_absolute_ritual_relic == null or not is_instance_valid(carried_absolute_ritual_relic):
		return
	var relic_visual: Node = carried_absolute_ritual_relic.get_node_or_null("RelicVisual")
	if relic_visual == null:
		relic_visual = carried_absolute_ritual_relic
	_set_visual_tree_visible(relic_visual, should_be_visible)


func _set_visual_tree_visible(node: Node, should_be_visible: bool) -> void:
	if node == null:
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = should_be_visible
	for child in node.get_children():
		_set_visual_tree_visible(child, should_be_visible)


func _move_into_cover() -> bool:
	if _hiding_target == null or not is_instance_valid(_hiding_target):
		return false
	var outward_normal: Vector3 = _hiding_collision_normal
	outward_normal.y = 0.0
	if outward_normal.length_squared() < 0.0001:
		outward_normal = global_position - _hiding_target.global_position
		outward_normal.y = 0.0
	if outward_normal.length_squared() < 0.0001:
		outward_normal = global_transform.basis.z
		outward_normal.y = 0.0
	if outward_normal.length_squared() < 0.0001:
		return false
	outward_normal = outward_normal.normalized()
	var to_player: Vector3 = global_position - _hiding_collision_point
	to_player.y = 0.0
	if to_player.length_squared() > 0.0001 and outward_normal.dot(to_player) < 0.0:
		outward_normal = -outward_normal
	var clearance: float = clampf(cover_surface_clearance, 0.1, 0.2)
	var destination := Vector3(_hiding_collision_point.x, global_position.y, _hiding_collision_point.z)
	var position_is_clear: bool = false
	for attempt in range(2):
		destination.x = _hiding_collision_point.x + outward_normal.x * clearance
		destination.z = _hiding_collision_point.z + outward_normal.z * clearance
		if _is_cover_position_clear(destination) and _is_cover_path_clear(global_position, destination):
			position_is_clear = true
			break
		clearance += 0.05
	if not position_is_clear:
		return false
	_cover_transition_active = true
	_tween_hiding_camera(true)
	_hiding_approach_tween = create_tween()
	_hiding_approach_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hiding_approach_tween.set_parallel(true)
	_hiding_approach_tween.tween_property(self, "global_position", destination, cover_approach_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hiding_approach_tween.finished.connect(_finish_cover_transition)
	return true


func _restore_from_cover() -> void:
	_update_crouch_state(Input.is_action_pressed("crouch"))
	var directions: Array[Vector3] = []
	var view_basis: Basis = global_transform.basis
	if camera != null and is_instance_valid(camera):
		view_basis = camera.global_transform.basis
	var camera_forward: Vector3 = -view_basis.z
	camera_forward.y = 0.0
	if camera_forward.length_squared() > 0.0001:
		directions.append(-camera_forward.normalized())
	var camera_right: Vector3 = view_basis.x
	camera_right.y = 0.0
	if camera_right.length_squared() > 0.0001:
		camera_right = camera_right.normalized()
		directions.append(camera_right)
		directions.append(-camera_right)
	var cover_normal: Vector3 = _hiding_collision_normal
	cover_normal.y = 0.0
	if cover_normal.length_squared() > 0.0001:
		directions.append(cover_normal.normalized())

	var destination: Vector3 = global_position
	var found_clear_position: bool = false
	for direction in directions:
		var distance: float = cover_exit_distance
		for attempt in range(8):
			var candidate: Vector3 = global_position + direction * distance
			if _is_cover_position_clear(candidate) and _is_cover_path_clear(global_position, candidate):
				destination = candidate
				found_clear_position = true
				break
			distance += 0.2
		if found_clear_position:
			break
	if not found_clear_position:
		destination = global_position
	_cover_transition_active = true
	_tween_hiding_camera(false, 0.3)
	_hiding_approach_tween = create_tween()
	_hiding_approach_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hiding_approach_tween.set_parallel(true)
	_hiding_approach_tween.tween_property(self, "global_position", destination, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hiding_approach_tween.finished.connect(_finish_cover_transition)
	_has_pre_hiding_transform = false


func _is_cover_position_clear(world_position: Vector3) -> bool:
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.shape == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	var body_transform := global_transform
	body_transform.origin = world_position
	query.transform = body_transform * collision.transform
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()


func _is_cover_path_clear(start: Vector3, finish: Vector3) -> bool:
	var sample_count: int = clampi(ceili(start.distance_to(finish) / 0.05), 1, 48)
	for step in range(1, sample_count + 1):
		var sample: Vector3 = start.lerp(finish, float(step) / float(sample_count))
		if not _is_cover_position_clear(sample):
			return false
	return true


func _cancel_cover_transition() -> void:
	if _hiding_approach_tween != null and _hiding_approach_tween.is_running():
		_hiding_approach_tween.kill()
	_cover_transition_active = false
	if not is_hiding:
		_update_crouch_state(is_crouching)


func _finish_cover_transition() -> void:
	_cover_transition_active = false
	velocity = Vector3.ZERO
	if not is_hiding:
		is_hidden = _hidden_by_zone
		_restore_hiding_collision()
		_set_carried_relic_visible(not is_hidden)
		if breath_label != null:
			breath_label.visible = false
		if not _exiting_cover.is_empty():
			var exit_state := _hiding_state_payload()
			exit_state.merge(_exiting_cover, true)
			_log("hide_exit_completed", exit_state)
			_exiting_cover.clear()
	_update_crouch_state(Input.is_action_pressed("crouch"))
	if _interaction_prompt != null:
		_update_interaction_prompt()


func collect_item(item_name: String, item_id: String = "") -> void:
	items_collected += 1
	if not item_id.is_empty() and not collected_item_ids.has(item_id):
		collected_item_ids.append(item_id)
	_log("item_collected", {"item": item_name, "collected": items_collected})
	item_collected.emit(item_name, items_collected, total_items_needed)
	_persist_campaign_level_progress()


func _persist_campaign_level_progress() -> void:
	_campaign_autosave_elapsed = 0.0
	var game_manager := get_node_or_null("/root/GameManager")
	var account := get_node_or_null("/root/CloudAccount")
	if game_manager == null or account == null or int(game_manager.get("active_save_slot")) < 1:
		return
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("make_campaign_level_progress_snapshot"):
		return
	var progress: Dictionary = level_builder.call("make_campaign_level_progress_snapshot", self)
	game_manager.call("set_level_progress", current_level_number, progress)
	var snapshot: Dictionary = game_manager.call("make_campaign_snapshot", current_level_number, false)
	account.call("queue_checkpoint", current_level_number, snapshot)


func _hiding_state_payload() -> Dictionary:
	return {
		"hidden": is_hidden,
		"hiding": is_hiding,
		"hidden_by_zone": _hidden_by_zone,
		"cover": str(_hiding_target.name) if is_instance_valid(_hiding_target) else "",
		"cover_type": current_cover_type,
	}


func set_hidden(hidden: bool) -> void:
	var changed := _hidden_by_zone != hidden
	_hidden_by_zone = hidden
	is_hidden = _hidden_by_zone or is_hiding
	if changed:
		_log("hiding_zone_entered" if hidden else "hiding_zone_left", _hiding_state_payload())
	_set_carried_relic_visible(not is_hidden)


func orient_toward(world_target: Vector3) -> void:
	var horizontal_target := world_target
	horizontal_target.y = global_position.y
	if global_position.distance_squared_to(horizontal_target) > 0.0001:
		look_at(horizontal_target, Vector3.UP)
	_pitch = 0.0
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		_camera_base_rotation = Vector3.ZERO
		_apply_camera_pose()


func freeze_controls() -> void:
	if is_hiding:
		_set_hiding(false)
	else:
		_cancel_cover_transition()
	controls_frozen = true
	is_running = false
	noise_level = 0.0
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _configure_collision_shape() -> void:
	# The authored shape supplies the standing dimensions used by crouching.
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is CapsuleShape3D:
		collision.shape = collision.shape.duplicate()
		collision_radius = (collision.shape as CapsuleShape3D).radius
		collision_height = (collision.shape as CapsuleShape3D).height


func _update_crouch_state(wants_to_crouch: bool) -> void:
	if is_crouching != wants_to_crouch:
		_log("crouch_started" if wants_to_crouch else "crouch_ended")
	is_crouching = wants_to_crouch
	var should_lower_posture: bool = is_crouching or is_hiding
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D if collision != null else null
	if capsule != null:
		var target_radius: float = hiding_collision_radius if is_hiding else collision_radius
		capsule.radius = target_radius
		var target_height := collision_height * (0.5 if should_lower_posture else 1.0)
		capsule.height = maxf(target_height, target_radius * 2.0)
		collision.position.y = -(collision_height - capsule.height) * 0.5 if should_lower_posture else 0.0
	_apply_camera_pose()


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("sprint", KEY_SHIFT)
	_remove_key_action("interact", KEY_E)
	_add_key_action("interact", KEY_F)
	_add_key_action("hide_interact", KEY_E)
	_add_key_action("health_skull_interact", KEY_R)
	_add_key_action("ritual_interact", KEY_Q)
	_add_key_action("absolute_ritual_interact", KEY_T)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("crouch", KEY_CTRL)
	_add_key_action("crouch", KEY_C)


func _add_key_action(action_name: StringName, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and (existing_event.physical_keycode == key or existing_event.keycode == key):
			return
	var key_event = InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action_name, key_event)


func _remove_key_action(action_name: StringName, key: Key) -> void:
	if not InputMap.has_action(action_name):
		return
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and (existing_event.physical_keycode == key or existing_event.keycode == key):
			InputMap.action_erase_event(action_name, existing_event)

func _bind_authored_nodes(node: Node) -> void:
	if node.has_meta("player_ref"):
		set(StringName(node.get_meta("player_ref")), node)
	if node.has_meta("player_array_ref"):
		var target_array: Array = get(StringName(node.get_meta("player_array_ref")))
		if not target_array.has(node):
			target_array.append(node)
	for child in node.get_children():
		_bind_authored_nodes(child)


func _log(kind: String, data: Dictionary = {}) -> void:
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.call("record", kind, data, global_position, current_level_number)

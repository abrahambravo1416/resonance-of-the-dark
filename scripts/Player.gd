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
const PUMPKIN_MARKER_COLOR_HEX: String = "#FF8800"
const PUMPKINS_REQUIRED: int = 7
const SFX_MENU_CLICK: AudioStreamWAV = preload("res://audio/Efectos cortos/click_menu.wav")
const SFX_HIDE: AudioStreamWAV = preload("res://audio/Efectos cortos/esconder_salir_escondite.wav")
const SFX_PUMPKIN: AudioStreamWAV = preload("res://audio/Efectos cortos/recoger_calabazas.wav")
const SFX_ENEMY_HIT: AudioStreamWAV = preload("res://audio/Efectos cortos/golpeo_de_enemigo.wav")
const SFX_EXIT_UNLOCK: AudioStreamWAV = preload("res://audio/Efectos cortos/desbloquear_salida.wav")
const SFX_LOSE: AudioStreamWAV = preload("res://audio/Efectos cortos/lose.wav")
const SFX_WALK: AudioStreamWAV = preload("res://audio/Efectos cortos/caminar.wav")

@export_group("References")
@export var camera: Camera3D
@export var interaction_ray: RayCast3D
@export var hiding_ray: RayCast3D

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
var current_cover_type: String = ""
var is_running: bool = false
var is_crouching: bool = false
var noise_level: float = 0.0
var items_collected: int = 0
var rituals_completed: int = 0
var pumpkins_collected: int = 0
var total_rituals_required: int = 4
var current_level_number: int = 1
var ritual_shrines: Array[RitualAltar] = []
var enemies: Array[CharacterBody3D] = []
var exit_unlocked: bool = false
var controls_frozen: bool = false
var is_dead: bool = false

var _noise_timer: float = 0.0
var _pitch: float = 0.0
var _standing_camera_height: float = 0.55
var _camera_base_position: Vector3 = Vector3.ZERO
var _regeneration_timer: float = 0.0
var _hidden_by_zone: bool = false
var _hiding_target: Node3D
var _hiding_collision_point: Vector3 = Vector3.ZERO
var _hiding_collision_normal: Vector3 = Vector3.ZERO
var _has_pre_hiding_transform: bool = false
var _hiding_approach_tween: Tween
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
var _radar_exit_gate_marker: Label
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
var _pumpkin_lock_message: Label
var _pumpkin_lock_timer: Timer
var _exit_gate_nearby: bool = false
var _has_escaped: bool = false
var _victory_screen_layer: CanvasLayer
var _damage_flash_layer: CanvasLayer
var _damage_flash_rect: ColorRect
var _damage_flash_tween: Tween
var _camera_shake_tween: Tween
var walk_audio_player: AudioStreamPlayer
var _level_2_intro_layer: CanvasLayer
var _level_2_intro_timer: Timer
var _level_2_intro_countdown: int = 5


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
		_camera_base_position = camera.position
	_create_threat_radar()
	_create_ritual_ui()
	_create_damage_feedback_ui()
	_create_footstep_player()
	_refresh_radar_enemies()
	if interaction_ray == null and camera != null:
		interaction_ray = camera.get_node_or_null("InteractionRay") as RayCast3D
	if interaction_ray != null:
		interaction_ray.add_exception(self)
		interaction_ray.collide_with_areas = true
	_configure_hiding_ray()
	_create_interaction_prompt()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if get_node_or_null("/root/LevelManager") != null:
		LevelManager.register_player(self)
	if current_health <= 0:
		_die()


func _process(delta: float) -> void:
	_update_threat_radar(delta)
	_update_interaction_prompt()
	if is_dead or current_health >= max_health:
		_regeneration_timer = 0.0
		return
	_regeneration_timer -= delta
	if _regeneration_timer <= 0.0:
		current_health = mini(current_health + 1, max_health)
		health_changed.emit(current_health, max_health)
		_regeneration_timer = regeneration_delay if current_health < max_health else 0.0


func _create_threat_radar() -> void:
	# The radar is a compact diegetic reticle rather than a rectangular HUD panel.
	_radar_layer = CanvasLayer.new()
	_radar_layer.name = "ThreatRadarLayer"
	_radar_layer.layer = 6
	add_child(_radar_layer)

	_radar_root = Control.new()
	_radar_root.name = "ThreatRadarHUD"
	_radar_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_radar_root.offset_left = 24.0
	_radar_root.offset_top = -194.0
	_radar_root.offset_right = 244.0
	_radar_root.offset_bottom = -20.0
	_radar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_layer.add_child(_radar_root)

	_radar_alert_label = Label.new()
	_radar_alert_label.name = "ThreatAlertState"
	_radar_alert_label.text = "ESTADO: PATRULLANDO"
	_radar_alert_label.position = Vector2(0.0, 149.0)
	_radar_alert_label.size = Vector2(220.0, 24.0)
	_radar_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radar_alert_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_radar_alert_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_alert_settings = LabelSettings.new()
	var radar_font := SystemFont.new()
	radar_font.font_names = PackedStringArray(["Arial", "DejaVu Sans", "sans-serif"])
	radar_font.font_weight = 700
	_radar_alert_settings.font = radar_font
	_radar_alert_settings.font_size = 14
	_radar_alert_settings.font_color = Color(0.2, 0.9, 0.4)
	_radar_alert_settings.outline_color = Color.BLACK
	_radar_alert_settings.outline_size = 8
	_radar_alert_settings.shadow_color = Color(0.2, 0.9, 0.4, 0.6)
	_radar_alert_settings.shadow_size = 5
	_radar_alert_settings.shadow_offset = Vector2(1.0, 1.0)
	_radar_alert_label.label_settings = _radar_alert_settings
	_radar_root.add_child(_radar_alert_label)

	_radar_arrow_area = Control.new()
	_radar_arrow_area.name = "RadarReticle"
	_radar_arrow_area.position = Vector2(52.0, 25.0)
	_radar_arrow_area.size = Vector2(116.0, 116.0)
	_radar_arrow_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_root.add_child(_radar_arrow_area)

	_radar_circle = Panel.new()
	_radar_circle.name = "RadarCircle"
	_radar_circle.size = Vector2(116.0, 116.0)
	_radar_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle_style := StyleBoxFlat.new()
	circle_style.bg_color = Color(0.05, 0.05, 0.08, 0.6)
	circle_style.border_color = Color(0.3, 0.8, 1.0, 0.4)
	circle_style.set_border_width_all(1)
	circle_style.set_corner_radius_all(58)
	_radar_circle.add_theme_stylebox_override("panel", circle_style)
	_radar_arrow_area.add_child(_radar_circle)

	var inner_ring := Panel.new()
	inner_ring.name = "RadarInnerRing"
	inner_ring.position = Vector2(22.0, 22.0)
	inner_ring.size = Vector2(72.0, 72.0)
	inner_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	ring_style.border_color = Color(0.3, 0.8, 1.0, 0.16)
	ring_style.set_border_width_all(1)
	ring_style.set_corner_radius_all(36)
	inner_ring.add_theme_stylebox_override("panel", ring_style)
	_radar_arrow_area.add_child(inner_ring)

	var reticle_line_color := Color(0.3, 0.8, 1.0, 0.28)
	_add_radar_line(Vector2(8.0, 57.5), Vector2(42.0, 1.0), reticle_line_color)
	_add_radar_line(Vector2(66.0, 57.5), Vector2(42.0, 1.0), reticle_line_color)
	_add_radar_line(Vector2(57.5, 8.0), Vector2(1.0, 42.0), reticle_line_color)
	_add_radar_line(Vector2(57.5, 66.0), Vector2(1.0, 42.0), reticle_line_color)

	_radar_center_glow = Panel.new()
	_radar_center_glow.name = "PlayerDotGlow"
	_radar_center_glow.position = Vector2(51.0, 51.0)
	_radar_center_glow.size = Vector2(14.0, 14.0)
	_radar_center_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0.8, 0.95, 1.0, 0.24)
	glow_style.set_corner_radius_all(7)
	_radar_center_glow.add_theme_stylebox_override("panel", glow_style)
	_radar_arrow_area.add_child(_radar_center_glow)

	_radar_center_dot = Panel.new()
	_radar_center_dot.name = "PlayerDot"
	_radar_center_dot.position = Vector2(55.0, 55.0)
	_radar_center_dot.size = Vector2(6.0, 6.0)
	_radar_center_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = Color(0.92, 0.98, 1.0, 1.0)
	dot_style.set_corner_radius_all(3)
	_radar_center_dot.add_theme_stylebox_override("panel", dot_style)
	_radar_arrow_area.add_child(_radar_center_dot)
	for index in total_rituals_required:
		var altar_marker := Label.new()
		altar_marker.name = "RitualMarker_%02d" % (index + 1)
		altar_marker.text = "◆"
		altar_marker.size = Vector2(16.0, 16.0)
		altar_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		altar_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		altar_marker.add_theme_font_size_override("font_size", 14)
		altar_marker.add_theme_color_override("font_color", Color(ALTAR_MARKER_COLOR_HEX))
		altar_marker.add_theme_color_override("font_outline_color", Color(0.06, 0.025, 0.0, 1.0))
		altar_marker.add_theme_constant_override("outline_size", 2)
		altar_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		altar_marker.visible = false
		_radar_arrow_area.add_child(altar_marker)
		_radar_altar_markers.append(altar_marker)

	_radar_arrow = Label.new()
	_radar_arrow.name = "ThreatArrow"
	_radar_arrow.text = "▲"
	_radar_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radar_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_radar_arrow.size = Vector2(16.0, 16.0)
	_radar_arrow.visible = false
	_radar_arrow.add_theme_font_size_override("font_size", 15)
	_radar_arrow.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.9))
	_radar_arrow.add_theme_color_override("font_outline_color", Color(0.05, 0.01, 0.02, 1.0))
	_radar_arrow.add_theme_constant_override("outline_size", 1)
	_radar_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_arrow_area.add_child(_radar_arrow)
	_radar_enemy_arrows.append(_radar_arrow)

	_radar_exit_gate_marker = Label.new()
	_radar_exit_gate_marker.name = "ExitGateMarker"
	_radar_exit_gate_marker.text = "■"
	_radar_exit_gate_marker.size = Vector2(10.0, 10.0)
	_radar_exit_gate_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radar_exit_gate_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_radar_exit_gate_marker.add_theme_font_size_override("font_size", 12)
	_radar_exit_gate_marker.add_theme_color_override("font_color", Color(EXIT_GATE_MARKER_COLOR_HEX))
	_radar_exit_gate_marker.add_theme_color_override("font_outline_color", Color(0.01, 0.04, 0.015, 1.0))
	_radar_exit_gate_marker.add_theme_constant_override("outline_size", 2)
	_radar_exit_gate_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_exit_gate_marker.visible = false
	_radar_arrow_area.add_child(_radar_exit_gate_marker)

	_radar_distance_label = Label.new()
	_radar_distance_label.name = "ThreatDistance"
	_radar_distance_label.text = "LEJANÍA DEL ENEMIGO: --.- m"
	_radar_distance_label.position = Vector2(0.0, 0.0)
	_radar_distance_label.size = Vector2(220.0, 17.0)
	_radar_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radar_distance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_radar_distance_label.add_theme_font_size_override("font_size", 13)
	_radar_distance_settings = LabelSettings.new()
	_radar_distance_settings.font_size = 13
	_radar_distance_settings.font_color = Color(0.7, 0.9, 1.0, 1.0)
	_radar_distance_settings.outline_color = Color(0.01, 0.025, 0.04, 0.9)
	_radar_distance_settings.outline_size = 2
	_radar_distance_settings.shadow_color = Color(0.3, 0.8, 1.0, 0.24)
	_radar_distance_settings.shadow_size = 3
	_radar_distance_settings.shadow_offset = Vector2(0.0, 1.0)
	_radar_distance_label.label_settings = _radar_distance_settings
	_radar_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_root.add_child(_radar_distance_label)

	_radar_root.visible = true


func _create_damage_feedback_ui() -> void:
	_damage_flash_layer = CanvasLayer.new()
	_damage_flash_layer.name = "DamageFeedbackLayer"
	_damage_flash_layer.layer = 7
	add_child(_damage_flash_layer)

	_damage_flash_rect = ColorRect.new()
	_damage_flash_rect.name = "DamageFlash"
	_damage_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash_rect.offset_left = 0.0
	_damage_flash_rect.offset_top = 0.0
	_damage_flash_rect.offset_right = 0.0
	_damage_flash_rect.offset_bottom = 0.0
	_damage_flash_rect.color = Color(1.0, 0.0, 0.0, 0.0)
	_damage_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash_layer.add_child(_damage_flash_rect)


func _add_radar_line(line_position: Vector2, line_size: Vector2, line_color: Color) -> void:
	var line := ColorRect.new()
	line.position = line_position
	line.size = line_size
	line.color = line_color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_arrow_area.add_child(line)


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
		var index: int = _radar_enemy_arrows.size()
		var arrow := Label.new()
		arrow.name = "ThreatArrow_%02d" % (index + 1)
		arrow.text = "▲"
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.size = Vector2(16.0, 16.0)
		arrow.visible = false
		arrow.add_theme_font_size_override("font_size", 15)
		arrow.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.9))
		arrow.add_theme_color_override("font_outline_color", Color(0.05, 0.01, 0.02, 1.0))
		arrow.add_theme_constant_override("outline_size", 1)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		return
	_update_ritual_radar_markers()
	_update_exit_gate_radar_marker()
	var radar_size: Vector2 = _radar_arrow_area.size
	var radar_center: Vector2 = radar_size * 0.5
	_update_health_skull_radar_markers(radar_center)
	_update_pumpkin_radar_markers(radar_center)
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
		var radar_radius: float = minf(39.0 + float(arrow_index) * 5.0, 49.0)
		var arrow_center: Vector2 = radar_center + Vector2(sin(angle), -cos(angle)) * radar_radius
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
			marker = Label.new()
			marker.name = "HealthSkullMarker_%d" % marker_id
			marker.text = "■"
			marker.size = Vector2(14.0, 14.0)
			marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			marker.add_theme_font_size_override("font_size", 14)
			marker.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
			marker.add_theme_color_override("font_outline_color", Color(0.02, 0.08, 0.2, 1.0))
			marker.add_theme_constant_override("outline_size", 2)
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_radar_arrow_area.add_child(marker)
			_radar_skull_markers[marker_id] = marker
		var toward_skull: Vector3 = skull_node.global_position - global_position
		toward_skull.y = 0.0
		if toward_skull.length_squared() < 0.0001:
			marker.visible = false
			continue
		var angle: float = _radar_relative_angle(skull_node.global_position)
		var radar_radius: float = clampf(toward_skull.length() / 30.0 * 50.0, 10.0, 50.0)
		var marker_center: Vector2 = radar_center + Vector2(sin(angle), -cos(angle)) * radar_radius
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
	if current_level_number != 3:
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
			marker = Label.new()
			marker.name = "PumpkinMarker_%d" % marker_id
			marker.text = "●"
			marker.size = Vector2(14.0, 14.0)
			marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			marker.add_theme_font_size_override("font_size", 14)
			marker.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))
			marker.add_theme_color_override("font_outline_color", Color(0.12, 0.035, 0.0, 1.0))
			marker.add_theme_constant_override("outline_size", 2)
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_radar_arrow_area.add_child(marker)
			_radar_pumpkin_markers[marker_id] = marker
		var toward_pumpkin: Vector3 = pumpkin_node.global_position - global_position
		toward_pumpkin.y = 0.0
		if toward_pumpkin.length_squared() < 0.0001:
			marker.visible = false
			continue
		var angle: float = _radar_relative_angle(pumpkin_node.global_position)
		var radar_radius: float = clampf(toward_pumpkin.length() / 35.0 * 50.0, 10.0, 50.0)
		var marker_center: Vector2 = radar_center + Vector2(sin(angle), -cos(angle)) * radar_radius
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


func set_ritual_shrines(altars: Array[RitualAltar]) -> void:
	ritual_shrines.clear()
	for altar in altars:
		if is_instance_valid(altar):
			ritual_shrines.append(altar)
	_refresh_ritual_shrines()
	_update_ritual_radar_markers()


func configure_level(level_number: int, ritual_count: int) -> void:
	current_level_number = clampi(level_number, 1, 3)
	total_rituals_required = maxi(1, ritual_count)
	rituals_completed = 0
	pumpkins_collected = 0
	exit_unlocked = false
	if _pumpkin_counter_label != null:
		_pumpkin_counter_label.visible = current_level_number == 3
	if current_level_number == 3:
		_pumpkin_counter_label.offset_top = 18.0
		_pumpkin_counter_label.offset_bottom = 50.0
		_ritual_counter_label.offset_top = 54.0
		_ritual_counter_label.offset_bottom = 88.0
		_ritual_mission_label.offset_top = 88.0
		_ritual_mission_label.offset_bottom = 116.0
	else:
		_ritual_counter_label.offset_top = 24.0
		_ritual_counter_label.offset_bottom = 60.0
		_ritual_mission_label.offset_top = 60.0
		_ritual_mission_label.offset_bottom = 88.0
	_update_ritual_counter_ui()


func show_level_intro(level_number: int) -> void:
	if current_level_number != level_number or level_number < 2 or _level_2_intro_layer != null:
		return
	get_tree().paused = true
	set_meta("level_2_intro_active", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_level_2_intro_countdown = 5
	_level_2_intro_layer = CanvasLayer.new()
	_level_2_intro_layer.name = "Level2IntroLayer"
	_level_2_intro_layer.layer = 40
	_level_2_intro_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_level_2_intro_layer)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.01, 0.03, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	_level_2_intro_layer.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.name = "Level2Announcement"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -390.0
	panel.offset_top = -230.0
	panel.offset_right = 390.0
	panel.offset_bottom = 230.0
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.025, 0.06, 0.99)
	panel_style.border_color = Color(0.24, 0.58, 0.95, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 30.0
	panel_style.content_margin_right = 30.0
	panel_style.content_margin_top = 26.0
	panel_style.content_margin_bottom = 26.0
	panel.add_theme_stylebox_override("panel", panel_style)
	_level_2_intro_layer.add_child(panel)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 18)
	layout.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_child(layout)

	var title := Label.new()
	title.text = "¡NIVEL 2: LA PESADILLA EXTENDIDA!" if level_number == 2 else "¡NIVEL 3: EL RITUAL FINAL!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
	layout.add_child(title)

	var instructions := Label.new()
	if level_number == 2:
		instructions.text = "NUEVA MECÁNICA: CRÁNEOS DE SALUD\n• Encuentra los cráneos en el suelo para recuperar 1 bloque de vida.\n• En el radar aparecerán marcados como un CUADRADO AZUL (■).\n• Si recoges los 3 cráneos, reaparecerán uno a uno cada 30 segundos."
	else:
		instructions.text = "MECÁNICA PRINCIPAL: LAS 7 CALABAZAS\n• Debes encontrar y recoger las 7 calabazas (● en el radar) usando la tecla 'E'.\n• Los altares permanecerán bloqueados hasta que reúnas todas las calabazas.\n• Recoge cráneos (■ azul) para curarte y mantente alerta de los 3 enemigos."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 17)
	instructions.add_theme_color_override("font_color", Color(0.92, 0.89, 0.96))
	layout.add_child(instructions)

	var countdown := Label.new()
	countdown.name = "Countdown"
	countdown.text = "El juego comienza en: 5..."
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown.add_theme_font_size_override("font_size", 22)
	countdown.add_theme_color_override("font_color", Color(1.0, 0.78, 0.36))
	layout.add_child(countdown)

	_level_2_intro_timer = Timer.new()
	_level_2_intro_timer.name = "Level2IntroCountdownTimer"
	_level_2_intro_timer.wait_time = 1.0
	_level_2_intro_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_level_2_intro_layer.add_child(_level_2_intro_timer)
	_level_2_intro_timer.timeout.connect(_on_level_2_intro_countdown)
	_level_2_intro_timer.start()


func _on_level_2_intro_countdown() -> void:
	_level_2_intro_countdown -= 1
	if _level_2_intro_countdown <= 0:
		_level_2_intro_layer.queue_free()
		_level_2_intro_layer = null
		_level_2_intro_timer = null
		set_meta("level_2_intro_active", false)
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var countdown_label := get_node_or_null("Level2IntroLayer/Level2Announcement/VBoxContainer/Countdown") as Label
	if countdown_label != null:
		countdown_label.text = "El juego comienza en: %d..." % _level_2_intro_countdown


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
		var angle: float = _radar_relative_angle(altar.global_position)
		var marker_center: Vector2 = radar_center + Vector2(sin(angle), -cos(angle)) * 42.0
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
	var angle: float = _radar_relative_angle(_radar_exit_gate_target.global_position)
	var marker_center: Vector2 = radar_center + Vector2(sin(angle), -cos(angle)) * 51.0
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
	if is_dead or amount <= 0:
		return
	var previous_health := current_health
	current_health = maxi(0, current_health - amount)
	if current_health == previous_health:
		return
	_regeneration_timer = regeneration_delay
	health_changed.emit(current_health, max_health)
	play_sound_effect(SFX_ENEMY_HIT)
	_play_damage_feedback()
	if current_health <= 0:
		_die()


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	current_health = mini(current_health + amount, max_health)
	_regeneration_timer = regeneration_delay if current_health < max_health else 0.0
	update_health_ui()


func update_health_ui() -> void:
	health_changed.emit(current_health, max_health)


func apply_knockback(impact_position: Vector3) -> void:
	if is_dead:
		return
	if is_hiding:
		_set_hiding(false)
	elif _cover_transition_active:
		_cancel_cover_transition()
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
	if camera == null or not is_instance_valid(camera):
		return
	if _camera_shake_tween != null and _camera_shake_tween.is_running():
		_camera_shake_tween.kill()
	var rest_position := _camera_rest_position()
	camera.position = rest_position
	_camera_shake_tween = create_tween()
	_camera_shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for _index in range(6):
		var shake_offset := Vector3(
			randf_range(-camera_shake_intensity, camera_shake_intensity),
			randf_range(-camera_shake_intensity * 0.65, camera_shake_intensity * 0.65),
			0.0
		)
		_camera_shake_tween.tween_property(camera, "position", rest_position + shake_offset, 0.025).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_shake_tween.tween_property(camera, "position", rest_position, 0.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _camera_rest_position() -> Vector3:
	var result := _camera_base_position
	var height_ratio: float = 1.0
	if is_crouching:
		height_ratio = 0.5
	if is_hiding:
		height_ratio = minf(height_ratio, hiding_camera_height_ratio)
	result.y = _standing_camera_height * height_ratio
	return result


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	play_sound_effect(SFX_LOSE, true)
	freeze_controls()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_died.emit()


func _unhandled_input(event: InputEvent) -> void:
	if controls_frozen or _cover_transition_active:
		return
	if event is InputEventMouseMotion and camera != null:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		camera.rotation.x = _pitch
	if event.is_action_pressed("ritual_interact"):
		_try_light_nearby_altar()
	if event.is_action_pressed("interact"):
		if current_level_number == 3 and _try_collect_nearby_pumpkin():
			return
		if is_hiding:
			play_sound_effect(SFX_HIDE)
			_set_hiding(false, null, true)
		else:
			_interact_with_target()


func _try_collect_nearby_pumpkin() -> bool:
	var level_builder := get_parent()
	if level_builder == null or not level_builder.has_method("try_collect_nearby_pumpkin"):
		return false
	return bool(level_builder.call("try_collect_nearby_pumpkin", self))


func collect_pumpkin() -> void:
	if current_level_number != 3 or pumpkins_collected >= PUMPKINS_REQUIRED:
		return
	pumpkins_collected += 1
	play_sound_effect(SFX_PUMPKIN)
	_update_ritual_counter_ui()


func _show_pumpkin_lock_message() -> void:
	if _pumpkin_lock_message == null or _pumpkin_lock_timer == null:
		return
	_pumpkin_lock_message.visible = true
	_pumpkin_lock_timer.start()


func _hide_pumpkin_lock_message() -> void:
	if _pumpkin_lock_message != null:
		_pumpkin_lock_message.visible = false


func _physics_process(delta: float) -> void:
	if controls_frozen:
		_update_footstep_audio(false)
		velocity = Vector3.ZERO
		return
	if _cover_transition_active:
		_update_footstep_audio(false)
		velocity = Vector3.ZERO
		return
	_update_crouch_state(Input.is_action_pressed("crouch"))

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if is_hiding:
		if input_vector.length_squared() > 0.01:
			_set_hiding(false, null, true)
			_update_footstep_audio(false)
			velocity = Vector3.ZERO
			return
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else -gravity * delta
		move_and_slide()
		_update_footstep_audio(false)
		_update_noise(delta, false)
		return
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
	if _knockback_time_remaining > 0.0:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		var knockback_decay: float = knockback_strength / maxf(knockback_duration, 0.01)
		_knockback_velocity.x = move_toward(_knockback_velocity.x, 0.0, knockback_decay * delta)
		_knockback_velocity.z = move_toward(_knockback_velocity.z, 0.0, knockback_decay * delta)
		_knockback_time_remaining = maxf(0.0, _knockback_time_remaining - delta)

	if is_on_floor():
		velocity.y = jump_velocity if not is_crouching and not is_hiding and Input.is_action_just_pressed("jump") else 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	var horizontal_motion: bool = absf(velocity.x) > 0.01 or absf(velocity.z) > 0.01
	var shift_pressed: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_action_pressed("sprint")
	_update_footstep_audio(is_on_floor() and horizontal_motion and shift_pressed)
	_update_noise(delta, input_vector.length_squared() > 0.0)


func _create_footstep_player() -> void:
	walk_audio_player = AudioStreamPlayer.new()
	walk_audio_player.name = "FootstepAudioPlayer"
	var walk_stream := SFX_WALK.duplicate() as AudioStreamWAV
	if walk_stream != null:
		walk_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	walk_audio_player.stream = walk_stream if walk_stream != null else SFX_WALK
	walk_audio_player.volume_db = -8.0
	walk_audio_player.process_mode = Node.PROCESS_MODE_INHERIT
	add_child(walk_audio_player)


func _update_footstep_audio(should_play: bool) -> void:
	if walk_audio_player == null or not is_instance_valid(walk_audio_player):
		return
	if should_play:
		if not walk_audio_player.playing:
			walk_audio_player.play()
	elif walk_audio_player.playing:
		walk_audio_player.stop()


func play_sound_effect(stream: AudioStream, process_always: bool = false) -> void:
	if stream == null:
		return
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = stream
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
	if hiding_ray == null:
		hiding_ray = RayCast3D.new()
		hiding_ray.name = "HidingRay"
		camera.add_child(hiding_ray)
	hiding_ray.target_position = Vector3(0.0, 0.0, -hiding_detection_distance)
	hiding_ray.collision_mask = 1
	hiding_ray.collide_with_areas = false
	hiding_ray.collide_with_bodies = true
	hiding_ray.enabled = true
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


func _create_interaction_prompt() -> void:
	if _radar_layer == null:
		return
	_interaction_prompt = Label.new()
	_interaction_prompt.name = "InteractionPrompt"
	_interaction_prompt.text = "[E] Esconderse detrás del objeto"
	_interaction_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_interaction_prompt.anchor_left = 0.5
	_interaction_prompt.anchor_right = 0.5
	_interaction_prompt.anchor_top = 1.0
	_interaction_prompt.anchor_bottom = 1.0
	_interaction_prompt.offset_left = -400.0
	_interaction_prompt.offset_right = 400.0
	_interaction_prompt.offset_top = -72.0
	_interaction_prompt.offset_bottom = -42.0
	_interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interaction_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction_prompt.visible = false
	var prompt_settings := LabelSettings.new()
	prompt_settings.font_size = 17
	prompt_settings.font_color = Color(0.85, 0.95, 1.0, 0.95)
	prompt_settings.outline_color = Color(0.01, 0.02, 0.03, 0.95)
	prompt_settings.outline_size = 4
	prompt_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.8)
	prompt_settings.shadow_size = 4
	prompt_settings.shadow_offset = Vector2(1.0, 2.0)
	_interaction_prompt.label_settings = prompt_settings
	_radar_layer.add_child(_interaction_prompt)


func _create_ritual_ui() -> void:
	if _radar_layer == null:
		return
	_pumpkin_counter_label = RichTextLabel.new()
	_pumpkin_counter_label.name = "PumpkinCounter"
	_pumpkin_counter_label.bbcode_enabled = true
	_pumpkin_counter_label.scroll_active = false
	_pumpkin_counter_label.fit_content = false
	_pumpkin_counter_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pumpkin_counter_label.offset_left = -720.0
	_pumpkin_counter_label.offset_right = -28.0
	_pumpkin_counter_label.offset_top = 18.0
	_pumpkin_counter_label.offset_bottom = 50.0
	_pumpkin_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pumpkin_counter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pumpkin_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pumpkin_counter_label.add_theme_font_size_override("normal_font_size", 17)
	_pumpkin_counter_label.add_theme_color_override("default_color", Color(1.0, 0.82, 0.62, 1.0))
	_pumpkin_counter_label.add_theme_color_override("font_outline_color", Color(0.08, 0.025, 0.0, 1.0))
	_pumpkin_counter_label.add_theme_constant_override("outline_size", 4)
	_pumpkin_counter_label.visible = false
	_radar_layer.add_child(_pumpkin_counter_label)

	_ritual_counter_label = Label.new()
	_ritual_counter_label.name = "RitualCounter"
	_ritual_counter_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ritual_counter_label.offset_left = -720.0
	_ritual_counter_label.offset_right = -28.0
	_ritual_counter_label.offset_top = 24.0
	_ritual_counter_label.offset_bottom = 60.0
	_ritual_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ritual_counter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ritual_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font_size = 18
	settings.font_color = Color(1.0, 0.78, 0.42, 0.98)
	settings.outline_color = Color(0.02, 0.015, 0.025, 0.95)
	settings.outline_size = 5
	settings.shadow_color = Color(0.0, 0.0, 0.0, 0.8)
	settings.shadow_size = 4
	settings.shadow_offset = Vector2(1.0, 2.0)
	_ritual_counter_label.label_settings = settings
	_radar_layer.add_child(_ritual_counter_label)

	_ritual_mission_label = RichTextLabel.new()
	_ritual_mission_label.name = "MissionObjective"
	_ritual_mission_label.bbcode_enabled = true
	_ritual_mission_label.scroll_active = false
	_ritual_mission_label.fit_content = false
	_ritual_mission_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ritual_mission_label.offset_left = -720.0
	_ritual_mission_label.offset_right = -28.0
	_ritual_mission_label.offset_top = 60.0
	_ritual_mission_label.offset_bottom = 88.0
	_ritual_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ritual_mission_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ritual_mission_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ritual_mission_label.add_theme_font_size_override("normal_font_size", 15)
	_ritual_mission_label.add_theme_color_override("default_color", Color(0.55, 1.0, 0.62, 0.95))
	_ritual_mission_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.025, 0.95))
	_ritual_mission_label.add_theme_constant_override("outline_size", 4)
	_radar_layer.add_child(_ritual_mission_label)
	_pumpkin_lock_message = Label.new()
	_pumpkin_lock_message.name = "PumpkinLockMessage"
	_pumpkin_lock_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pumpkin_lock_message.anchor_left = 0.5
	_pumpkin_lock_message.anchor_right = 0.5
	_pumpkin_lock_message.offset_left = -430.0
	_pumpkin_lock_message.offset_right = 430.0
	_pumpkin_lock_message.offset_top = 132.0
	_pumpkin_lock_message.offset_bottom = 174.0
	_pumpkin_lock_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pumpkin_lock_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pumpkin_lock_message.text = "¡Debes recolectar las 7 calabazas antes de realizar los rituales!"
	_pumpkin_lock_message.add_theme_font_size_override("font_size", 18)
	_pumpkin_lock_message.add_theme_color_override("font_color", Color(1.0, 0.72, 0.42, 1.0))
	_pumpkin_lock_message.add_theme_color_override("font_outline_color", Color(0.08, 0.025, 0.0, 1.0))
	_pumpkin_lock_message.add_theme_constant_override("outline_size", 5)
	_pumpkin_lock_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pumpkin_lock_message.visible = false
	_radar_layer.add_child(_pumpkin_lock_message)
	_pumpkin_lock_timer = Timer.new()
	_pumpkin_lock_timer.name = "PumpkinLockMessageTimer"
	_pumpkin_lock_timer.one_shot = true
	_pumpkin_lock_timer.wait_time = 2.5
	_pumpkin_lock_timer.timeout.connect(_hide_pumpkin_lock_message)
	_radar_layer.add_child(_pumpkin_lock_timer)
	_update_ritual_counter_ui()


func _update_interaction_prompt() -> void:
	if _interaction_prompt == null:
		return
	if _has_escaped:
		_interaction_prompt.visible = false
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
		_interaction_prompt.text = "[Q] Encender ritual"
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
	if current_level_number == 3 and pumpkins_collected < PUMPKINS_REQUIRED:
		_show_pumpkin_lock_message()
		return
	if not altar.activate():
		return
	rituals_completed = mini(rituals_completed + 1, total_rituals_required)
	ritual_progress_changed.emit(rituals_completed, total_rituals_required)
	_update_ritual_counter_ui()
	noise_emitted.emit(altar.global_position, 1.0)
	if rituals_completed >= total_rituals_required:
		play_sound_effect(SFX_EXIT_UNLOCK)
		exit_unlocked = true
		_update_ritual_counter_ui()
		cemetery_exit_unlocked.emit()


func _update_ritual_counter_ui() -> void:
	if _pumpkin_counter_label != null:
		_pumpkin_counter_label.visible = current_level_number == 3
		_pumpkin_counter_label.text = "Calabazas recolectadas: %d / %d ([color=%s]●[/color])" % [pumpkins_collected, PUMPKINS_REQUIRED, PUMPKIN_MARKER_COLOR_HEX]
	if _ritual_counter_label != null:
		if exit_unlocked:
			_ritual_counter_label.text = "PORTÓN PRINCIPAL ABIERTO, ESCAPA!!!"
		else:
			_ritual_counter_label.text = "Rituales completados: %d / %d" % [rituals_completed, total_rituals_required]
	if _ritual_mission_label != null:
		if exit_unlocked and rituals_completed >= total_rituals_required:
			_ritual_mission_label.text = "- Sigue el ([color=%s]■[/color]) para salir" % EXIT_GATE_MARKER_COLOR_HEX
		elif current_level_number == 3 and pumpkins_collected < PUMPKINS_REQUIRED:
			_ritual_mission_label.text = "- Reúne las 7 calabazas para desbloquear los altares"
		else:
			_ritual_mission_label.text = "- Enciende los altares ([color=%s]◆[/color])" % ALTAR_MARKER_COLOR_HEX


func can_escape_cemetery() -> bool:
	return exit_unlocked and rituals_completed >= total_rituals_required


func set_exit_gate_nearby(nearby: bool) -> void:
	_exit_gate_nearby = nearby
	_update_interaction_prompt()


func escape_cemetery() -> void:
	if _has_escaped or not can_escape_cemetery():
		return
	_has_escaped = true
	freeze_controls()
	if _interaction_prompt != null:
		_interaction_prompt.visible = false
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		if enemy_node.has_method("freeze_for_escape"):
			enemy_node.call("freeze_for_escape")
	if current_level_number < 3:
		_show_level_complete_screen()
	else:
		_show_final_victory_screen()


func _show_level_complete_screen() -> void:
	_show_escape_screen(
		"¡NIVEL %d COMPLETADO!" % current_level_number,
		"Sobreviviste a esta noche...",
		true
	)


func _show_final_victory_screen() -> void:
	_show_escape_screen(
		"¡HAS ESCAPADO DEFINITIVAMENTE!",
		"El cementerio queda atrás. Por fin estás a salvo.",
		false
	)


func _show_escape_screen(title_text: String, description_text: String, show_continue: bool) -> void:
	if _victory_screen_layer != null:
		return
	_victory_screen_layer = CanvasLayer.new()
	_victory_screen_layer.name = "EscapeTransitionLayer"
	_victory_screen_layer.layer = 30
	_victory_screen_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_victory_screen_layer)

	var full_screen := Control.new()
	full_screen.name = "EscapeTransitionScreen"
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_victory_screen_layer.add_child(full_screen)

	var backdrop := ColorRect.new()
	backdrop.name = "EscapeBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.01, 0.025, 0.9)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	full_screen.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.name = "EscapePanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360.0
	panel.offset_top = -190.0
	panel.offset_right = 360.0
	panel.offset_bottom = 190.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.025, 0.055, 0.97)
	panel_style.border_color = Color(0.55, 0.28, 0.2, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 28.0
	panel_style.content_margin_right = 28.0
	panel_style.content_margin_top = 24.0
	panel_style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", panel_style)
	full_screen.add_child(panel)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)

	var title := Label.new()
	title.name = "EscapeTitle"
	title.text = title_text
	title.custom_minimum_size.y = 70.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_settings := LabelSettings.new()
	title_settings.font_size = 30 if show_continue else 32
	title_settings.font_color = Color(0.92, 0.75, 0.52) if show_continue else Color(0.55, 1.0, 0.65)
	title_settings.outline_color = Color(0.02, 0.01, 0.025, 1.0)
	title_settings.outline_size = 8
	title_settings.shadow_color = Color(0.75, 0.3, 0.12, 0.55) if show_continue else Color(0.1, 0.8, 0.25, 0.65)
	title_settings.shadow_size = 10
	title_settings.shadow_offset = Vector2(0.0, 0.0)
	title.label_settings = title_settings
	layout.add_child(title)

	var description := Label.new()
	description.name = "EscapeDescription"
	description.text = description_text
	description.custom_minimum_size.y = 36.0
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 18)
	description.add_theme_color_override("font_color", Color(0.78, 0.76, 0.82))
	layout.add_child(description)

	if show_continue:
		var continue_button := _make_escape_button("CONTINUAR AL NIVEL %d" % (current_level_number + 1), true)
		continue_button.pressed.connect(_continue_to_next_level)
		layout.add_child(continue_button)
	var menu_button := _make_escape_button("MENÚ PRINCIPAL", not show_continue)
	menu_button.pressed.connect(_return_to_main_menu)
	layout.add_child(menu_button)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _make_escape_button(button_text: String, highlighted: bool) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(360.0, 52.0)
	button.pressed.connect(_play_menu_click)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.98, 0.92, 0.82))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.32, 0.13, 0.09) if highlighted else Color(0.12, 0.1, 0.16)
	normal.border_color = Color(0.82, 0.42, 0.22) if highlighted else Color(0.38, 0.32, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.48, 0.19, 0.11) if highlighted else Color(0.2, 0.16, 0.26)
	hover.border_color = Color(1.0, 0.68, 0.38)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _play_menu_click() -> void:
	play_sound_effect(SFX_MENU_CLICK, true)


func _continue_to_next_level() -> void:
	get_tree().paused = false
	var next_level_path := "res://scenes/Level_%02d.tscn" % (current_level_number + 1)
	var error := get_tree().change_scene_to_file(next_level_path)
	if error != OK:
		push_error("No se pudo cargar el Nivel %d (error %d)." % [current_level_number + 1, error])


func _return_to_main_menu() -> void:
	get_tree().paused = false
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
		is_hiding = true
		is_running = false
		_hiding_target = target
		current_cover_type = "leaf_tree" if _is_leaf_tree_cover(target) else "object"
		is_hidden = _hidden_by_zone or is_hiding
		_update_crouch_state(is_crouching)
		if not _move_into_cover():
			is_hiding = false
			current_cover_type = ""
			_hiding_target = null
			is_hidden = _hidden_by_zone
			_has_pre_hiding_transform = false
			_update_crouch_state(is_crouching)
		else:
			play_sound_effect(SFX_HIDE)
	else:
		if not is_hiding:
			return
		_cancel_cover_transition()
		is_hiding = false
		current_cover_type = ""
		_hiding_target = null
		is_hidden = _hidden_by_zone
		if restore_position and _has_pre_hiding_transform:
			_restore_from_cover()
		else:
			_update_crouch_state(is_crouching)
			_has_pre_hiding_transform = false
	if _interaction_prompt != null:
		_update_interaction_prompt()


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
	_hiding_approach_tween = create_tween()
	_hiding_approach_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hiding_approach_tween.set_parallel(true)
	_hiding_approach_tween.tween_property(self, "global_position", destination, cover_approach_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hiding_approach_tween.finished.connect(_finish_cover_transition)
	return true


func _restore_from_cover() -> void:
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
	_hiding_approach_tween = create_tween()
	_hiding_approach_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hiding_approach_tween.set_parallel(true)
	_hiding_approach_tween.tween_property(self, "global_position", destination, cover_approach_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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
	_update_crouch_state(Input.is_action_pressed("crouch"))


func collect_item(item_name: String) -> void:
	items_collected += 1
	item_collected.emit(item_name, items_collected, total_items_needed)


func set_hidden(hidden: bool) -> void:
	_hidden_by_zone = hidden
	is_hidden = _hidden_by_zone or is_hiding


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
	if camera != null:
		var camera_ratio: float = 1.0
		if is_crouching:
			camera_ratio = 0.5
		if is_hiding:
			camera_ratio = minf(camera_ratio, hiding_camera_height_ratio)
		camera.position.y = _standing_camera_height * camera_ratio


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("interact", KEY_E)
	_add_key_action("ritual_interact", KEY_Q)
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

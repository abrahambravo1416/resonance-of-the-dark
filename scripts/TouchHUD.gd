extends CanvasLayer
## UI táctil editable. El personaje recibe exactamente las mismas acciones que en PC.
@export var debug_on_pc: bool = false
@onready var controls: Control = $TouchControls
@onready var joystick: Control = $TouchControls/VirtualJoystick
@onready var look: Control = $TouchControls/LookArea
@onready var interaction: TouchScreenButton = $TouchControls/InteractionPrompt
@onready var pause_button: TouchScreenButton = $Pause
@onready var settings_panel: Control = $SettingsPanel
var player: Node
var _settings_paused_before: bool = false
var _previous_visible: bool = false
var _safe_rect := Rect2()
var _saved_layouts: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	get_node("/root/ControlSettings").changed.connect(_apply_settings)
	get_viewport().size_changed.connect(_layout)
	$SettingsPanel/Card/Margin/Scroll/Fields/Close.pressed.connect(close_settings)
	$SettingsPanel/Card/Margin/Scroll/Fields/ResetDefaults.pressed.connect(_reset_settings)
	$SettingsPanel/Card/Margin/Scroll/Fields/VibrationRow/TestVibration.pressed.connect(_test_vibration)
	var fields := $SettingsPanel/Card/Margin/Scroll/Fields
	var config := get_node("/root/ControlSettings")
	for item in [["Opacity", "opacity"], ["Size", "control_scale"], ["DeadZone", "dead_zone"], ["LookSensitivity", "look_sensitivity"]]:
		var slider: Range = fields.get_node(item[0])
		slider.value = config.get(item[1])
		slider.value_changed.connect(func(value: float): config.set(item[1], value); config.save())
	fields.get_node("VibrationRow/Vibration").button_pressed = config.vibration
	fields.get_node("VibrationRow/Vibration").toggled.connect(_on_vibration_toggled)
	fields.get_node("DebugTouch").button_pressed = config.debug_touch
	fields.get_node("DebugTouch").visible = OS.has_feature("debug") and _is_desktop_platform()
	fields.get_node("DebugTouch").toggled.connect(func(value: bool): config.debug_touch = value; config.save())
	settings_panel.hide()
	_apply_settings()

func _enabled() -> bool:
	return get_node("/root/ControlSettings").touch_enabled() or (OS.has_feature("debug") and debug_on_pc)

func _is_desktop_platform() -> bool:
	return OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]

func _process(_delta: float) -> void:
	var candidate := get_tree().get_first_node_in_group("player")
	if player != candidate:
		_restore_layouts()
		player = candidate
		if is_instance_valid(player):
			_layout()
	var playable: bool = is_instance_valid(player) and not get_tree().paused and not player.controls_frozen and not player.is_dead
	controls.visible = _enabled() and playable
	pause_button.visible = playable
	if controls.visible != _previous_visible:
		release_controls()
		_previous_visible = controls.visible
		if controls.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_layout()
		else:
			_restore_layouts()
	if not controls.visible: return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var context: Dictionary = player.get_touch_interaction()
	for layer in get_tree().get_nodes_in_group("narrative_layers"):
		layer.hint.hide()
		# Wrapped text can temporarily inflate a Container while anchors change.
		layer.panel.size = Vector2(550, 159)
		if context.is_empty() and is_instance_valid(layer._nearest):
			context = {"action": "narrative_interact", "text": "Hablar / recordar"}
	# Keep the held action until release; never switch a pressed button's binding.
	if not interaction.is_pressed():
		interaction.visible = not context.is_empty()
		interaction.action = context.get("action", "interact")
		interaction.caption = context.get("text", "Interactuar")
		interaction.queue_redraw()
	if player._interaction_prompt != null: player._interaction_prompt.hide()

func _on_vibration_toggled(enabled: bool) -> void:
	var config := get_node("/root/ControlSettings")
	config.vibration = enabled
	config.save()

func _test_vibration() -> void:
	var config := get_node("/root/ControlSettings")
	config.vibration = true
	$SettingsPanel/Card/Margin/Scroll/Fields/VibrationRow/Vibration.set_pressed_no_signal(true)
	config.save()
	config.test_haptic()

func release_controls() -> void:
	joystick.release_touch()
	look.release_touch()
	get_node("/root/UnifiedInput").release_virtual()

func _apply_settings() -> void:
	var config := get_node("/root/ControlSettings")
	controls.modulate.a = config.opacity
	var fields := $SettingsPanel/Card/Margin/Scroll/Fields
	fields.get_node("OpacityLabel").text = "Opacidad: " + str(roundi(config.opacity * 100)) + "%"
	fields.get_node("SizeLabel").text = "Tamaño de controles: " + str(roundi(config.control_scale * 100)) + "%"
	fields.get_node("DeadZoneLabel").text = "Zona muerta del joystick: " + String.num(float(config.dead_zone), 2)
	fields.get_node("LookSensitivityLabel").text = "Velocidad de giro táctil: " + str(roundi(config.look_sensitivity * 100.0)) + "%"
	fields.get_node("Opacity").set_value_no_signal(config.opacity)
	fields.get_node("Size").set_value_no_signal(config.control_scale)
	fields.get_node("DeadZone").set_value_no_signal(config.dead_zone)
	fields.get_node("LookSensitivity").set_value_no_signal(config.look_sensitivity)
	fields.get_node("VibrationRow/Vibration").button_pressed = config.vibration
	fields.get_node("DebugTouch").button_pressed = config.debug_touch
	joystick.dead_zone = config.dead_zone
	release_controls()
	_layout()

func calculate_safe_rect(view_size: Vector2, safe_pixels: Rect2, window_pixels: Rect2) -> Rect2:
	if safe_pixels.size.x <= 0 or safe_pixels.size.y <= 0 or window_pixels.size.x <= 0 or window_pixels.size.y <= 0:
		return Rect2(Vector2.ZERO, view_size)
	var clipped := safe_pixels.intersection(window_pixels)
	if not clipped.has_area(): return Rect2(Vector2.ZERO, view_size)
	var factor := view_size / window_pixels.size
	return Rect2((clipped.position - window_pixels.position) * factor, clipped.size * factor)

func _layout() -> void:
	if not is_node_ready(): return
	var view := get_viewport().get_visible_rect().size
	var window := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	_safe_rect = calculate_safe_rect(view, Rect2(DisplayServer.get_display_safe_area()), window) if get_node("/root/ControlSettings").touchscreen_available else Rect2(Vector2.ZERO, view)
	controls.position = _safe_rect.position
	controls.size = _safe_rect.size
	var area := _safe_rect.size
	var scale_factor: float = get_node("/root/ControlSettings").control_scale
	var radius: float = 100.0 * scale_factor
	joystick.joystick_radius = radius
	joystick.size = Vector2.ONE * radius * 2
	joystick.position = Vector2(26, area.y - radius * 2 - 28)
	look.position = Vector2(area.x * 0.43, 140)
	look.size = Vector2(area.x * 0.57, maxf(0, area.y - 370))
	for item in [["Jump", Vector2(area.x - 82 * scale_factor, area.y - 210 * scale_factor)], ["Sprint", Vector2(area.x - 208 * scale_factor, area.y - 84 * scale_factor)], ["Crouch", Vector2(area.x - 82 * scale_factor, area.y - 84 * scale_factor)]]:
		var button: Node2D = controls.get_node(item[0])
		button.position = item[1]
		button.scale = Vector2.ONE * scale_factor
	pause_button.position = _safe_rect.position + Vector2(area.x * 0.5, 66.0 * scale_factor)
	pause_button.scale = Vector2.ONE * scale_factor
	interaction.position = Vector2(area.x * 0.5, area.y - 75 * scale_factor)
	interaction.scale = Vector2.ONE * scale_factor
	$SettingsPanel.position = _safe_rect.position
	$SettingsPanel.size = area
	var card: Control = $SettingsPanel/Card
	var card_width: float = minf(620.0, maxf(280.0, area.x - 32.0))
	var card_height: float = minf(620.0, maxf(280.0, area.y - 24.0))
	card.offset_left = -card_width * 0.5
	card.offset_right = card_width * 0.5
	card.offset_top = -card_height * 0.5
	card.offset_bottom = card_height * 0.5
	if is_instance_valid(player) and _enabled():
		var radar: Control = player.get_node("ThreatRadarLayer/ThreatRadarHUD")
		_remember_layout(radar)
		radar.set_anchors_preset(Control.PRESET_TOP_LEFT)
		radar.position = _safe_rect.position + Vector2(20, 180)
		radar.scale = Vector2.ONE * 0.9
		for narrative in get_tree().get_nodes_in_group("narrative_layers"):
			_remember_layout(narrative.panel)
			narrative.panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
			narrative.panel.position = _safe_rect.position + Vector2(area.x * 0.5 - 275, area.y - 340)
			narrative.panel.size = Vector2(550, 159)

func open_settings() -> void:
	_apply_settings()
	_settings_paused_before = get_tree().paused
	get_tree().paused = true
	settings_panel.show()
	release_controls()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_settings() -> void:
	get_node("/root/ControlSettings").save()
	settings_panel.hide()
	get_tree().paused = _settings_paused_before
	if is_instance_valid(player) and not _enabled() and not get_tree().paused: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _reset_settings() -> void:
	get_node("/root/ControlSettings").reset_to_defaults()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready(): release_controls()

func _remember_layout(control: Control) -> void:
	if _saved_layouts.has(control): return
	var values: Dictionary = {}
	for property in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom", "scale"]:
		values[property] = control.get(property)
	_saved_layouts[control] = values

func _restore_layouts() -> void:
	for control in _saved_layouts:
		if is_instance_valid(control):
			for property in _saved_layouts[control]: control.set(property, _saved_layouts[control][property])
	_saved_layouts.clear()

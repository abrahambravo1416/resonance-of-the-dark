extends Node
## Merges virtual and physical sources. Releasing a finger never cancels a held key/pad.
var virtual_sources: Dictionary = {}
var mouse_delta := Vector2.ZERO
var look_delta := Vector2.ZERO
const KEYS = {"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S, "jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_C, "hide_interact": KEY_E, "interact": KEY_F, "ritual_interact": KEY_Q, "absolute_ritual_interact": KEY_T, "health_skull_interact": KEY_R, "narrative_interact": KEY_G, "pause_game": KEY_P}
const AXES = {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0], "look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0], "look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0]}
const BUTTONS = {"ui_accept": JOY_BUTTON_A, "jump": JOY_BUTTON_A, "sprint": JOY_BUTTON_LEFT_SHOULDER, "crouch": JOY_BUTTON_B, "interact": JOY_BUTTON_X, "hide_interact": JOY_BUTTON_Y, "ui_cancel": JOY_BUTTON_START, "narrative_interact": JOY_BUTTON_DPAD_UP, "ritual_interact": JOY_BUTTON_DPAD_LEFT, "health_skull_interact": JOY_BUTTON_DPAD_DOWN, "absolute_ritual_interact": JOY_BUTTON_DPAD_RIGHT}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	for action in KEYS:
		ensure_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[action]
		if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)
	for action in AXES:
		ensure_action(action)
		var event := InputEventJoypadMotion.new()
		event.axis = AXES[action][0]
		event.axis_value = AXES[action][1]
		if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)
	for action in BUTTONS:
		ensure_action(action)
		var event := InputEventJoypadButton.new()
		event.button_index = BUTTONS[action]
		if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)
	for action in ["look_pointer_left", "look_pointer_right", "look_pointer_up", "look_pointer_down"]: ensure_action(action)

func ensure_action(action: String) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action, 0.2)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.device != InputEvent.DEVICE_ID_EMULATION:
		mouse_delta += event.relative

func set_virtual(source: String, action: String, strength: float) -> void:
	ensure_action(action)
	if not virtual_sources.has(action): virtual_sources[action] = {}
	if strength > 0.0: virtual_sources[action][source] = clampf(strength, 0, 1)
	else: virtual_sources[action].erase(source)
	_merge(action)

func _physical_strength(action: String) -> float:
	var strength := 0.0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (Input.is_physical_key_pressed(event.physical_keycode) if event.physical_keycode else Input.is_key_pressed(event.keycode)):
			strength = 1.0
		elif event is InputEventJoypadButton:
			for device in Input.get_connected_joypads():
				if Input.is_joy_button_pressed(device, event.button_index): strength = 1.0
		elif event is InputEventJoypadMotion:
			for device in Input.get_connected_joypads():
				var value := maxf(0, Input.get_joy_axis(device, event.axis) * signf(event.axis_value))
				if value >= 0.2: strength = maxf(strength, value)
	return strength

func _merge(action: String) -> void:
	var strength := _physical_strength(action)
	for value in virtual_sources.get(action, {}).values(): strength = maxf(strength, float(value))
	if strength > 0.0:
		if not Input.is_action_pressed(action) or not is_equal_approx(Input.get_action_raw_strength(action), strength): Input.action_press(action, strength)
	elif Input.is_action_pressed(action): Input.action_release(action)

func _physics_process(_delta: float) -> void:
	for action in AXES: _merge(action)
	for action in virtual_sources: _merge(action)
	var combined := mouse_delta + look_delta
	mouse_delta = Vector2.ZERO
	look_delta = Vector2.ZERO
	# Convert pointer displacement to action strengths; Player reads only Input Map.
	for entry in [["look_pointer_right", combined.x], ["look_pointer_left", -combined.x], ["look_pointer_down", combined.y], ["look_pointer_up", -combined.y]]:
		set_virtual("pointer", entry[0], maxf(0, float(entry[1]) / 4096.0))

func release_virtual() -> void:
	for action in virtual_sources:
		virtual_sources[action].clear()
		_merge(action)
	mouse_delta = Vector2.ZERO
	look_delta = Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: release_virtual()

extends Node
signal changed
const DEFAULT_OPACITY: float = 0.4
const DEFAULT_CONTROL_SCALE: float = 1.0
const DEFAULT_DEAD_ZONE: float = 0.15
const DEFAULT_LOOK_SENSITIVITY: float = 1.3
const DEFAULT_VIBRATION: bool = true
const SETTINGS_VERSION: int = 5
var settings_path: String = OS.get_environment("RESONANCE_CONTROL_CONFIG") if not OS.get_environment("RESONANCE_CONTROL_CONFIG").is_empty() else "user://touch_controls.cfg"
var opacity: float = DEFAULT_OPACITY
var control_scale: float = DEFAULT_CONTROL_SCALE
var dead_zone: float = DEFAULT_DEAD_ZONE
var look_sensitivity: float = DEFAULT_LOOK_SENSITIVITY
var vibration: bool = DEFAULT_VIBRATION
var debug_touch: bool = false
var touchscreen_available: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Godot also reports emulated mouse touches as touchscreen availability.
	touchscreen_available = DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	if OS.has_feature("web"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		touchscreen_available = bool(bridge.eval("navigator.maxTouchPoints > 0"))
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		opacity = clampf(float(config.get_value("touch", "opacity", DEFAULT_OPACITY)), 0.1, 1.0)
		control_scale = clampf(float(config.get_value("touch", "scale", DEFAULT_CONTROL_SCALE)), 0.9, 1.5)
		dead_zone = clampf(float(config.get_value("touch", "dead_zone", DEFAULT_DEAD_ZONE)), 0.05, 0.35)
		var saved_look_sensitivity: Variant = config.get_value("touch", "look_sensitivity", null)
		look_sensitivity = clampf(float(saved_look_sensitivity) if saved_look_sensitivity != null else DEFAULT_LOOK_SENSITIVITY, 0.5, 2.0)
		var saved_settings_version: int = int(config.get_value("touch", "settings_version", 1))
		if saved_settings_version < 2:
			# 1.0 was the previous default; migrate it to the new 130% default.
			if saved_look_sensitivity == null or is_equal_approx(look_sensitivity, 1.0):
				look_sensitivity = DEFAULT_LOOK_SENSITIVITY
			config.set_value("touch", "look_sensitivity", look_sensitivity)
			config.set_value("touch", "settings_version", 2)
			config.save(settings_path)
		vibration = bool(config.get_value("touch", "vibration", DEFAULT_VIBRATION))
		debug_touch = bool(config.get_value("touch", "debug_touch", false))
		if saved_settings_version < SETTINGS_VERSION:
			# Earlier Android builds lacked VIBRATE permission. Their saved-off state
			# prevented every gameplay pulse, so enable haptics once after upgrading.
			vibration = true
			config.set_value("touch", "vibration", true)
			config.set_value("touch", "settings_version", SETTINGS_VERSION)
			config.save(settings_path)

func touch_enabled() -> bool:
	return touchscreen_available or (OS.has_feature("debug") and (debug_touch or OS.get_environment("RESONANCE_TOUCH_DEBUG") == "1"))

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("touch", "opacity", opacity)
	config.set_value("touch", "scale", control_scale)
	config.set_value("touch", "dead_zone", dead_zone)
	config.set_value("touch", "look_sensitivity", look_sensitivity)
	config.set_value("touch", "settings_version", SETTINGS_VERSION)
	config.set_value("touch", "vibration", vibration)
	config.set_value("touch", "debug_touch", debug_touch)
	config.save(settings_path)
	changed.emit()

func reset_to_defaults() -> void:
	opacity = DEFAULT_OPACITY
	control_scale = DEFAULT_CONTROL_SCALE
	dead_zone = DEFAULT_DEAD_ZONE
	look_sensitivity = DEFAULT_LOOK_SENSITIVITY
	vibration = DEFAULT_VIBRATION
	debug_touch = false
	save()

func haptic(ms: int = 40) -> void:
	if not vibration:
		return
	# Keep light feedback short and make important events unmistakable with a
	# distinct double/triple pulse. The amplitude is the maximum supported by
	# Godot's handheld API; Android still applies the device's haptic settings.
	var pulse_count: int = 1 if ms < 140 else (2 if ms < 220 else 3)
	var pulse_duration: int = clampi(ms, 120, 240)
	for pulse_index in range(pulse_count):
		Input.vibrate_handheld(pulse_duration, 1.0)
		if pulse_index < pulse_count - 1:
			await get_tree().create_timer(0.12, true).timeout


func test_haptic() -> void:
	if not vibration:
		return
	# A deliberate, unmistakable pattern for the settings screen: three strong
	# pulses with short gaps, longer than regular pickup feedback.
	for pulse_index in range(3):
		Input.vibrate_handheld(240, 1.0)
		if pulse_index < 2:
			await get_tree().create_timer(0.16, true).timeout

func _input(event: InputEvent) -> void:
	# Also enable real touch hardware on desktop, without mistaking mouse emulation for it.
	if event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION and not touchscreen_available:
		touchscreen_available = true
		changed.emit()

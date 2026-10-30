extends Node
signal changed
const DEFAULT_OPACITY: float = 0.4
const DEFAULT_CONTROL_SCALE: float = 0.9
const DEFAULT_DEAD_ZONE: float = 0.15
const DEFAULT_VIBRATION: bool = true
var settings_path: String = OS.get_environment("RESONANCE_CONTROL_CONFIG") if not OS.get_environment("RESONANCE_CONTROL_CONFIG").is_empty() else "user://touch_controls.cfg"
var opacity: float = DEFAULT_OPACITY
var control_scale: float = DEFAULT_CONTROL_SCALE
var dead_zone: float = DEFAULT_DEAD_ZONE
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
		vibration = bool(config.get_value("touch", "vibration", DEFAULT_VIBRATION))
		debug_touch = bool(config.get_value("touch", "debug_touch", false))

func touch_enabled() -> bool:
	return touchscreen_available or (OS.has_feature("debug") and (debug_touch or OS.get_environment("RESONANCE_TOUCH_DEBUG") == "1"))

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("touch", "opacity", opacity)
	config.set_value("touch", "scale", control_scale)
	config.set_value("touch", "dead_zone", dead_zone)
	config.set_value("touch", "vibration", vibration)
	config.set_value("touch", "debug_touch", debug_touch)
	config.save(settings_path)
	changed.emit()

func reset_to_defaults() -> void:
	opacity = DEFAULT_OPACITY
	control_scale = DEFAULT_CONTROL_SCALE
	dead_zone = DEFAULT_DEAD_ZONE
	vibration = DEFAULT_VIBRATION
	debug_touch = false
	save()

func haptic(ms: int = 40) -> void:
	if vibration and OS.get_name() in ["Android", "iOS"]:
		Input.vibrate_handheld(clampi(ms, 30, 80))

func _input(event: InputEvent) -> void:
	# Also enable real touch hardware on desktop, without mistaking mouse emulation for it.
	if event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION and not touchscreen_available:
		touchscreen_available = true
		changed.emit()

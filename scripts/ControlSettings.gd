extends Node
signal changed
var settings_path: String = OS.get_environment("RESONANCE_CONTROL_CONFIG") if not OS.get_environment("RESONANCE_CONTROL_CONFIG").is_empty() else "user://touch_controls.cfg"
var opacity: float = 0.55
var control_scale: float = 1.0
var dead_zone: float = 0.2
var vibration: bool = true
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
		opacity = clampf(float(config.get_value("touch", "opacity", 0.55)), 0.4, 0.7)
		control_scale = clampf(float(config.get_value("touch", "scale", 1.0)), 0.9, 1.35)
		dead_zone = clampf(float(config.get_value("touch", "dead_zone", 0.2)), 0.15, 0.25)
		vibration = bool(config.get_value("touch", "vibration", true))
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

func haptic(ms: int = 40) -> void:
	if vibration and OS.get_name() in ["Android", "iOS"]:
		Input.vibrate_handheld(clampi(ms, 30, 80))

func _input(event: InputEvent) -> void:
	# Also enable real touch hardware on desktop, without mistaking mouse emulation for it.
	if event is InputEventScreenTouch and event.device != InputEvent.DEVICE_ID_EMULATION and not touchscreen_available:
		touchscreen_available = true
		changed.emit()

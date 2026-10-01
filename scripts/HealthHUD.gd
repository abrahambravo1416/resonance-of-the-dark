extends CanvasLayer

const HEALTH_BLOCK_COUNT := 4
const ACTIVE_COLOR := Color("d94a3d")
const EMPTY_COLOR := Color("342c3a")

var _blocks: Array[ColorRect] = []
var _player: Node


func _ready() -> void:
	_build_interface()
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var callback := Callable(self, "_on_health_changed")
	if _player.has_signal("health_changed") and not _player.is_connected("health_changed", callback):
		_player.connect("health_changed", callback)
	_on_health_changed(int(_player.get("current_health")), int(_player.get("max_health")))


func _build_interface() -> void:
	var root := Control.new()
	root.name = "HealthHUD"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var container := VBoxContainer.new()
	container.name = "HealthContainer"
	container.position = Vector2(28.0, 26.0)
	container.add_theme_constant_override("separation", 8)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(container)

	var heading := Label.new()
	heading.text = "VIDA"
	heading.add_theme_color_override("font_color", Color("e2c7a5"))
	heading.add_theme_font_size_override("font_size", 14)
	container.add_child(heading)

	var row := HBoxContainer.new()
	row.name = "HealthBlocks"
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(row)

	for index in HEALTH_BLOCK_COUNT:
		var frame := PanelContainer.new()
		frame.name = "HealthBlock%d" % (index + 1)
		frame.custom_minimum_size = Vector2(34.0, 18.0)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color("120f18")
		frame_style.border_color = Color("706071")
		frame_style.set_border_width_all(1)
		frame_style.set_corner_radius_all(3)
		frame_style.content_margin_left = 3.0
		frame_style.content_margin_right = 3.0
		frame_style.content_margin_top = 3.0
		frame_style.content_margin_bottom = 3.0
		frame.add_theme_stylebox_override("panel", frame_style)
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.color = EMPTY_COLOR
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(fill)
		row.add_child(frame)
		_blocks.append(fill)


func _on_health_changed(current_health: int, max_health: int) -> void:
	var visible_blocks := clampi(current_health, 0, mini(max_health, HEALTH_BLOCK_COUNT))
	for index in _blocks.size():
		_blocks[index].color = ACTIVE_COLOR if index < visible_blocks else EMPTY_COLOR
		_blocks[index].modulate.a = 1.0 if index < visible_blocks else 0.55

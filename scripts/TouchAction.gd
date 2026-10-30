extends TouchScreenButton
@export var caption: String = "Saltar"
@export var button_size := Vector2(108, 108)

func _ready() -> void:
	pressed.connect(_pressed)
	released.connect(_released)
	var rectangle := RectangleShape2D.new()
	rectangle.size = button_size
	shape = rectangle
	visibility_changed.connect(queue_redraw)

func _pressed() -> void:
	get_node("/root/UnifiedInput").set_virtual(str(get_instance_id()), action, 1.0)
	get_node("/root/ControlSettings").haptic(40)
	queue_redraw()

func _released() -> void:
	get_node("/root/UnifiedInput").set_virtual(str(get_instance_id()), action, 0.0)
	queue_redraw()

func _draw() -> void:
	var is_pause: bool = action == "ui_cancel"
	var icon_color: Color
	if is_pause:
		var pause_bg: Color = Color(0.64, 0.36, 0.15, 0.42) if is_pressed() else Color(0.38, 0.22, 0.10, 0.22)
		var pause_border := Color(0.95, 0.71, 0.36, 0.48)
		var radius: float = minf(button_size.x, button_size.y) * 0.5 - 1.0
		draw_circle(Vector2.ZERO, radius, pause_bg)
		draw_circle(Vector2.ZERO, radius - 1.0, pause_border, false, 2.0, true)
		icon_color = Color(1.0, 0.94, 0.80, 0.78)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("617e70") if is_pressed() else Color("102625")
		style.border_color = Color("c5d9ba")
		style.set_corner_radius_all(22)
		style.set_border_width_all(2)
		draw_style_box(style, Rect2(-button_size * 0.5, button_size))
		icon_color = Color("#e3eed5")
	match action:
		"ui_accept":
			_draw_arrow(Vector2.UP, icon_color)
		"crouch":
			_draw_arrow(Vector2.DOWN, icon_color)
		"sprint":
			_draw_sprint(icon_color)
		"ui_cancel":
			draw_rect(Rect2(Vector2(-13, -20), Vector2(8, 40)), icon_color, true)
			draw_rect(Rect2(Vector2(5, -20), Vector2(8, 40)), icon_color, true)
		_:
			var font := ThemeDB.fallback_font
			var font_size: int = 21 if button_size.x > 150 else 19
			var measured := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			if measured.x > button_size.x - 14:
				font_size = maxi(14, int(font_size * (button_size.x - 14) / measured.x))
				measured = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			draw_string(font, Vector2(-measured.x * 0.5, 7), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, icon_color)


func _draw_arrow(direction: Vector2, color: Color) -> void:
	var tip: Vector2 = direction * 22.0
	var tail: Vector2 = -direction * 19.0
	var side := Vector2(-direction.y, direction.x)
	var arrow_base: Vector2 = tip - direction * 15.0
	draw_line(tail, tip, color, 6.0, true)
	draw_line(tip, arrow_base + side * 13.0, color, 6.0, true)
	draw_line(tip, arrow_base - side * 13.0, color, 6.0, true)


func _draw_sprint(color: Color) -> void:
	_draw_chevron(-8.0, color)
	_draw_chevron(12.0, color)


func _draw_chevron(center_x: float, color: Color) -> void:
	var start := Vector2(center_x - 10.0, -17.0)
	var tip := Vector2(center_x + 8.0, 0.0)
	var end := Vector2(center_x - 10.0, 17.0)
	draw_line(start, tip, color, 6.0, true)
	draw_line(tip, end, color, 6.0, true)

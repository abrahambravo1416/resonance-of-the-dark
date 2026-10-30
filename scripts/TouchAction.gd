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
	var style := StyleBoxFlat.new()
	style.bg_color = Color("617e70") if is_pressed() else Color("102625")
	style.border_color = Color("c5d9ba")
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	draw_style_box(style, Rect2(-button_size * 0.5, button_size))
	var font := ThemeDB.fallback_font
	var font_size := 21 if button_size.x > 150 else 19
	var measured := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if measured.x > button_size.x - 14:
		font_size = maxi(14, int(font_size * (button_size.x - 14) / measured.x))
		measured = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-measured.x * 0.5, 7), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e3eed5"))

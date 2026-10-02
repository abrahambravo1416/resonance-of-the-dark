extends Control

const LEVEL_SCENE := "res://scenes/Level_01.tscn"

var _title: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_interface()
	_animate_title()


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color("0d0d0d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow := ColorRect.new()
	glow.name = "NightGlow"
	glow.color = Color("1a0933")
	glow.anchor_left = 0.0
	glow.anchor_top = 0.0
	glow.anchor_right = 1.0
	glow.anchor_bottom = 0.55
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var layout := VBoxContainer.new()
	layout.name = "MenuLayout"
	layout.set_anchors_preset(Control.PRESET_CENTER)
	layout.anchor_left = 0.5
	layout.anchor_top = 0.5
	layout.anchor_right = 0.5
	layout.anchor_bottom = 0.5
	layout.offset_left = -260.0
	layout.offset_top = -240.0
	layout.offset_right = 260.0
	layout.offset_bottom = 240.0
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 24)
	add_child(layout)

	var eyebrow := Label.new()
	eyebrow.text = "✦  UNA NOCHE DE PENUMBRA  ✦"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color", Color("c28b45"))
	eyebrow.add_theme_font_size_override("font_size", 16)
	layout.add_child(eyebrow)

	_title = Label.new()
	_title.name = "GameTitle"
	_title.text = "RESONANCE\nOF THE DARK"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color("f2d5a0"))
	_title.add_theme_color_override("font_shadow_color", Color("d95e27"))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	_title.add_theme_font_size_override("font_size", 48)
	layout.add_child(_title)

	var subtitle := Label.new()
	subtitle.text = "EL SILENCIO TAMBIÉN TE ESCUCHA"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("a99caf"))
	subtitle.add_theme_font_size_override("font_size", 13)
	layout.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8.0
	layout.add_child(spacer)

	var play_button := _make_button("JUGAR", true)
	play_button.pressed.connect(_start_game)
	layout.add_child(play_button)

	var exit_button := _make_button("SALIR", false)
	exit_button.pressed.connect(_quit_game)
	layout.add_child(exit_button)

	var footer := Label.new()
	footer.text = "WASD MOVER  ·  SHIFT CORRER  ·  CTRL AGACHAR  ·  E/Q INTERACTUAR"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color("746b7c"))
	footer.add_theme_font_size_override("font_size", 11)
	layout.add_child(footer)


func _make_button(label_text: String, highlighted: bool) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(280.0, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("fff0d4"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("f2d5a0"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("58251f") if highlighted else Color("211a2b")
	normal.border_color = Color("c77738") if highlighted else Color("66566f")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("773426") if highlighted else Color("33253e")
	hover.border_color = Color("f0a34c")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _animate_title() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_title, "modulate", Color("#ffd29b"), 1.8)
	tween.tween_property(_title, "modulate", Color("#d99a70"), 1.8)


func _start_game() -> void:
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _quit_game() -> void:
	get_tree().quit()

extends Control

const LEVEL_SCENE := "res://scenes/Level_01.tscn"
const SFX_MENU_CLICK: AudioStreamWAV = preload("res://audio/Efectos cortos/click_menu.wav")

var _title: Label
var _high_score_label: Label
var _vignette_material: ShaderMaterial


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_node("/root/LevelManager").call("set_gameplay_hud_visible", false)
	var music_player := get_node_or_null("MenuMusicPlayer") as AudioStreamPlayer
	if music_player != null:
		if music_player.stream is AudioStreamOggVorbis:
			(music_player.stream as AudioStreamOggVorbis).loop = true
		if not music_player.playing:
			music_player.play()
	_build_interface()
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_update_vignette_aspect):
		viewport.size_changed.connect(_update_vignette_aspect)
	_animate_title()


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := TextureRect.new()
	background.name = "Background"
	var gradient := Gradient.new()
	gradient.set_color(0, Color("190B28"))
	gradient.set_color(1, Color("0B0B0B"))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 2
	gradient_texture.height = 512
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)
	background.texture = gradient_texture
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_add_vignette_overlay()

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
	var title_settings := LabelSettings.new()
	title_settings.font_color = Color("f2d5a0")
	title_settings.font_size = 48
	title_settings.shadow_color = Color(0.015, 0.005, 0.025, 0.82)
	title_settings.shadow_size = 9
	title_settings.shadow_offset = Vector2(0.0, 4.0)
	_title.label_settings = title_settings
	layout.add_child(_title)

	var subtitle := Label.new()
	subtitle.text = "EL SILENCIO TAMBIÉN TE ESCUCHA"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("a99caf"))
	subtitle.add_theme_font_size_override("font_size", 13)
	layout.add_child(subtitle)

	_high_score_label = Label.new()
	_high_score_label.name = "HighScore"
	_high_score_label.text = "MEJOR PUNTUACIÓN: %d" % get_node("/root/GameManager").get("high_score")
	_high_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_high_score_label.add_theme_color_override("font_color", Color("f0a34c"))
	_high_score_label.add_theme_font_size_override("font_size", 16)
	layout.add_child(_high_score_label)

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

	var score_penalty_hint := Label.new()
	score_penalty_hint.name = "ScorePenaltyHint"
	score_penalty_hint.text = "GAME OVER = -50 en puntuación final"
	score_penalty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_penalty_hint.add_theme_color_override("font_color", Color("746b7c"))
	score_penalty_hint.add_theme_font_size_override("font_size", 11)
	layout.add_child(score_penalty_hint)


func _add_vignette_overlay() -> void:
	var vignette_shader := Shader.new()
	vignette_shader.code = """
shader_type canvas_item;
uniform vec4 vignette_color : source_color = vec4(0.008, 0.003, 0.016, 0.62);
uniform float vignette_strength = 0.72;
uniform float aspect_ratio = 1.7778;

void fragment() {
	vec2 centered_uv = (UV - vec2(0.5)) * vec2(aspect_ratio, 1.0);
	float distance_from_center = length(centered_uv);
	float edge_mask = smoothstep(0.42, 1.02, distance_from_center);
	COLOR = vec4(vignette_color.rgb, edge_mask * vignette_color.a * vignette_strength);
}
"""
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = vignette_shader
	var vignette := ColorRect.new()
	vignette.name = "EdgeVignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = _vignette_material
	add_child(vignette)
	_update_vignette_aspect()


func _update_vignette_aspect() -> void:
	if _vignette_material == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_vignette_material.set_shader_parameter("aspect_ratio", viewport_size.x / maxf(viewport_size.y, 1.0))


func _make_button(label_text: String, highlighted: bool) -> Button:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(_play_menu_click)
	button.custom_minimum_size = Vector2(280.0, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("fff0d4"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("f2d5a0"))
	button.add_theme_color_override("font_shadow_color", Color(0.01, 0.005, 0.02, 0.82))
	button.add_theme_constant_override("shadow_offset_x", 0)
	button.add_theme_constant_override("shadow_offset_y", 2)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("58251f") if highlighted else Color("211a2b")
	normal.border_color = Color("c77738") if highlighted else Color("66566f")
	normal.shadow_color = Color(0.005, 0.002, 0.012, 0.72)
	normal.shadow_size = 10
	normal.shadow_offset = Vector2(0.0, 4.0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("773426") if highlighted else Color("33253e")
	hover.border_color = Color("f0a34c")
	hover.shadow_size = 12
	hover.shadow_offset = Vector2(0.0, 5.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _play_menu_click() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = SFX_MENU_CLICK
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _animate_title() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_title, "modulate", Color("#ffd29b"), 1.8)
	tween.tween_property(_title, "modulate", Color("#d99a70"), 1.8)


func _start_game() -> void:
	get_node("/root/GameManager").reset_run()
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _quit_game() -> void:
	get_tree().quit()

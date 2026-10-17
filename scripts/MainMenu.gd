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
	_title = $MenuLayout/GameTitle
	_high_score_label = $MenuLayout/HighScore
	_high_score_label.text = "MEJOR PUNTUACIÓN: %d" % get_node("/root/GameManager").get("high_score")
	_vignette_material = $EdgeVignette.material as ShaderMaterial
	# Play the click while the menu still belongs to the tree. Scene changes run last.
	for button in [$MenuLayout/PlayButton, $MenuLayout/SkipMenuButton, $MenuLayout/ExitButton]:
		button.pressed.connect(_play_menu_click)
	$MenuLayout/PlayButton.pressed.connect(_start_game)
	$MenuLayout/SkipMenuButton.pressed.connect(_start_game.bind(true))
	$MenuLayout/ExitButton.pressed.connect(_quit_game)
	_update_vignette_aspect()


func _update_vignette_aspect() -> void:
	if _vignette_material == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_vignette_material.set_shader_parameter("aspect_ratio", viewport_size.x / maxf(viewport_size.y, 1.0))


func _play_menu_click() -> void:
	var player := preload("res://scenes/ui/SoundEffect.tscn").instantiate() as AudioStreamPlayer
	player.stream = SFX_MENU_CLICK
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _animate_title() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(_title, "modulate", Color("#ffd29b"), 1.8)
	tween.tween_property(_title, "modulate", Color("#d99a70"), 1.8)


func _start_game(skip_intro: bool = false) -> void:
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		var alias_text := ($MenuLayout/PlayerAlias as LineEdit).text.strip_edges()
		logger.call("start_session", alias_text if not alias_text.is_empty() else "Visitante")
		logger.call("record", "menu_skipped" if skip_intro else "menu_start", {"skip_intro": skip_intro})
	get_node("/root/GameManager").reset_run()
	get_node("/root/GameManager").set("skip_next_intro", skip_intro)
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _quit_game() -> void:
	get_tree().quit()

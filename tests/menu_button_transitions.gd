extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func settle_scene() -> void:
	for frame in range(8):
		await process_frame

func _run() -> void:
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await settle_scene()
	current_scene.get_node("MenuLayout/PlayButton").pressed.emit()
	await settle_scene()
	check(current_scene.scene_file_path.ends_with("Level_01.tscn"), "Play button opens first level")
	var player := current_scene.get_node("Player")
	check(paused and player._level_2_intro_layer != null, "Normal play preserves intro")
	player._level_2_intro_layer.get_node("Level2Announcement/Content/SkipMenuButton").pressed.emit()
	await process_frame
	check(not paused, "Intro skip button resumes gameplay")
	current_scene.get_node("PauseMenu")._toggle_pause()
	current_scene.get_node("PauseMenu/PauseOverlay/PauseLayout/ResumeButton").pressed.emit()
	check(not paused, "Pause resume button works")
	current_scene.get_node("PauseMenu")._toggle_pause()
	current_scene.get_node("PauseMenu/PauseOverlay/PauseLayout/MenuButton").pressed.emit()
	await settle_scene()
	check(current_scene.scene_file_path.ends_with("MainMenu.tscn"), "Pause menu button changes scene safely")
	current_scene.get_node("MenuLayout/SkipMenuButton").pressed.emit()
	await settle_scene()
	player = current_scene.get_node("Player")
	check(not paused and player._level_2_intro_layer == null, "Main skip button bypasses only intro")
	player.take_damage(100)
	check(paused, "Real death opens game over")
	current_scene.get_node("GameOverMenu/GameOverOverlay/GameOverLayout/RestartButton").pressed.emit()
	await settle_scene()
	player = current_scene.get_node("Player")
	check(not player.is_dead and player.current_health == player.max_health, "Game over restart button reloads original level")
	player._finish_level_intro()
	player.take_damage(100)
	current_scene.get_node("GameOverMenu/GameOverOverlay/GameOverLayout/MenuButton").pressed.emit()
	await settle_scene()
	check(current_scene.scene_file_path.ends_with("MainMenu.tscn"), "Game over menu button changes scene safely")
	current_scene.get_node("MenuLayout/SkipMenuButton").pressed.emit()
	await settle_scene()
	player = current_scene.get_node("Player")
	player._show_escape_screen("Complete", "Button transition regression", true)
	player._victory_screen_layer.get_node("EscapeTransitionScreen/EscapePanel/Content/ContinueButton").pressed.emit()
	await settle_scene()
	check(current_scene.scene_file_path.ends_with("Level_02.tscn"), "Completion continue button opens next original level")
	player = current_scene.get_node("Player")
	player._finish_level_intro()
	player._show_escape_screen("Complete", "Button transition regression", true)
	player._victory_screen_layer.get_node("EscapeTransitionScreen/EscapePanel/Content/MenuButton").pressed.emit()
	await settle_scene()
	check(current_scene.scene_file_path.ends_with("MainMenu.tscn"), "Completion menu button changes scene safely")
	current_scene.free()
	current_scene = null
	# Headless audio does not drain short sounds before this rapid test ends.
	for sound in root.get_children():
		if sound is AudioStreamPlayer:
			sound.stop()
			sound.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("MENU_BUTTON_TRANSITIONS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

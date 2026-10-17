extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failures.append(explanation)
		push_error(explanation)

func _run() -> void:
	var menu: Control = load("res://scenes/MainMenu.tscn").instantiate()
	var title: Label = menu.get_node("MenuLayout/GameTitle")
	title.text = "EDITOR TITLE TEST"
	var menu_nodes := menu.find_children("*", "", true, false).size()
	root.add_child(menu)
	check(title.text == "EDITOR TITLE TEST", "Menu title edited in the scene survives ready")
	check(menu.find_children("*", "", true, false).size() == menu_nodes, "Menu does not procedurally add controls")
	check(menu.has_node("MenuLayout/SkipMenuButton"), "Main menu has editable skip button")
	check(menu.has_node("MenuLayout/PlayerAlias"), "Main menu has editable alias field")
	menu.free()
	var holder := Node3D.new()
	root.add_child(holder)
	var player: CharacterBody3D = load("res://scenes/actors/Player.tscn").instantiate()
	player.camera.position.y = 0.73
	player.walk_speed = 4.1
	(player.get_node("CollisionShape3D").shape as CapsuleShape3D).radius = 0.34
	var prompt: Label = player.get_node("ThreatRadarLayer/InteractionPrompt")
	prompt.label_settings = prompt.label_settings.duplicate()
	prompt.label_settings.font_size = 27
	holder.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	check(is_equal_approx(player._standing_camera_height, 0.73), "Authored camera height is retained")
	check(is_equal_approx(player.walk_speed, 4.1), "Inspector walk speed is retained")
	check(is_equal_approx(player.collision_radius, 0.34), "Authored collision radius is retained")
	check(prompt.label_settings.font_size == 27, "Authored HUD font size is retained")
	check(player._radar_altar_markers.size() == 4, "All four authored altar markers bind")
	check(player._radar_enemy_arrows.size() == 1, "Authored enemy marker binds once")
	check(player.walk_audio_player != null, "Authored footsteps bind")
	check(player.hiding_animation.has_animation("hide_enter"), "Hide entry animation is editable")
	check(player.hiding_animation.has_animation("hide_exit"), "Hide exit animation is editable")
	player.hiding_animation.play("hide_enter")
	player.hiding_animation.advance(0.28)
	player._apply_camera_pose()
	check(player.camera.rotation.z < -0.02, "Hide animation rolls camera visually")
	player.hiding_animation.play("hide_exit")
	player.hiding_animation.advance(player.hiding_animation.get_animation("hide_exit").length)
	player._apply_camera_pose()
	check(is_zero_approx(player.camera.rotation.z), "Exit animation restores camera roll")
	for number in range(1,5):
		player.current_level_number = number
		player.show_level_intro(number)
		check(player._level_2_intro_layer != null, "Level %d intro opens" % number)
		check(player._level_2_intro_layer.has_node("Level2Announcement/Content/SkipMenuButton"), "Level %d intro skip button exists" % number)
		check(player.countdown_time == [5,10,15,15][number - 1], "Level %d original countdown preserved" % number)
		player._on_transition_skip_requested()
		check(not paused and not player.get_meta("level_2_intro_active"), "Level %d skip resumes gameplay" % number)
		await process_frame
	root.get_node("GameManager").skip_next_intro = true
	player.current_level_number = 1
	player.show_level_intro(1)
	check(player._level_2_intro_layer == null and not paused, "Main menu skip bypasses only visual intro")
	check(not root.get_node("GameManager").skip_next_intro, "Skip flag is consumed once")
	player._show_escape_screen("Test completed", "Same scoring", true)
	check(player._victory_screen_layer.has_node("EscapeTransitionScreen/EscapePanel/Content/ContinueButton"), "Completion screen binds editable continue button")
	player._victory_screen_layer.free()
	player._victory_screen_layer = null
	paused = false
	player._show_escape_screen("Test victory", "Same scoring", false)
	check(player._victory_screen_layer.has_node("EscapeTransitionScreen/EscapePanel/Content/MenuButton"), "Victory screen binds editable menu button")
	player._victory_screen_layer.free()
	player._victory_screen_layer = null
	paused = false
	for scene in ["PauseMenu", "GameOverMenu", "HealthHUD"]:
		var ui: CanvasLayer = load("res://scenes/ui/%s.tscn" % scene).instantiate()
		var count := ui.find_children("*", "", true, false).size()
		holder.add_child(ui)
		check(ui.find_children("*", "", true, false).size() == count, "%s binds saved controls without rebuilding" % scene)
		ui.free()
	holder.free()
	print("EDITABLE_PLAYER_UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

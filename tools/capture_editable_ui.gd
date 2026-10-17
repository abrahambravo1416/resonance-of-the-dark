extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func _run() -> void:
	root.size = Vector2i(1152, 648)
	var menu: Control = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await capture("/private/tmp/resonance-menu-1152.png")
	root.size = Vector2i(1920, 1080)
	await capture("/private/tmp/resonance-menu-1920.png")
	root.remove_child(menu)
	menu.free()
	var level: Node3D = load("res://scenes/Level_01.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	for index in 20:
		await process_frame
	await capture("/private/tmp/resonance-intro-1920.png")
	var player := level.get_node("Player")
	player.call("_finish_level_intro")
	await capture("/private/tmp/resonance-gameplay-1920.png")
	root.size = Vector2i(1152, 648)
	await capture("/private/tmp/resonance-gameplay-1152.png")
	root.remove_child(level)
	level.free()
	quit()

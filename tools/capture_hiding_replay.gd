extends SceneTree

var capture_origin := Vector3.ZERO

func nearest_cover_first(a: Node3D, b: Node3D) -> bool:
	return a.global_position.distance_squared_to(capture_origin) < b.global_position.distance_squared_to(capture_origin)

func _initialize() -> void:
	call_deferred("_run")

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "/private/tmp/resonance-hide-%s.png" % label
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("GameManager").skip_next_intro = true
	var logger := root.get_node("GameplayLog")
	logger.launch_local_dashboard = false
	logger.start_session("Verificación: enemigos y escondite")
	var level: Node3D = load("res://scenes/Level_01.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await create_timer(6.5).timeout
	var player := level.get_node("Player") as PlayerController
	var found := false
	var covers := get_nodes_in_group("hide_objects")
	capture_origin = player.global_position
	covers.sort_custom(nearest_cover_first)
	for cover_node: Node3D in covers:
		for direction: Vector3 in [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]:
			player.global_position = Vector3(cover_node.global_position.x, 0.87, cover_node.global_position.z) + direction * 1.8
			player.velocity = Vector3.ZERO
			player.orient_toward(cover_node.global_position)
			for frame in range(8):
				await physics_frame
			var target := player._get_hiding_cover_target()
			if target == null or not player.is_on_floor():
				continue
			await capture("standing")
			player._set_hiding(true, target)
			if player.is_hiding:
				print("ACTUAL COVER ", target.name, " at ", player.global_position)
				found = true
				break
		if found:
			break
	if not found:
		push_error("No physical cover usable for capture")
		logger.end_session("verification_failed")
		level.free()
		quit(1)
		return
	await create_timer(0.1).timeout
	await capture("entering")
	await create_timer(0.6).timeout
	await capture("hidden")
	await create_timer(2.0).timeout
	player._set_hiding(false, null, true)
	await create_timer(0.12).timeout
	await capture("exiting")
	await create_timer(0.4).timeout
	await capture("restored")
	await create_timer(0.6).timeout
	logger.end_session("verification_complete")
	print("HIDING_REPLAY_CAPTURE complete")
	covers.clear()
	change_scene_to_file("res://scenes/MainMenu.tscn")
	for frame in range(8):
		await process_frame
	quit()

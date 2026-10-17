extends SceneTree

var checks := 0
var failures: Array[String] = []
var player: PlayerController
var world: Node3D
var cover: StaticBody3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true).timeout

func box_body(label: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	return body

func face_cover() -> void:
	player.global_position = Vector3(0.0, 0.86, 0.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.orient_toward(Vector3(0.0, 0.86, -2.0))
	for frame in range(8):
		await physics_frame
	player._apply_camera_pose()

func press_hide() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	player._unhandled_input(event)

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	box_body("Floor", Vector3(0, -0.25, 0), Vector3(16, 0.5, 16))
	cover = box_body("EditableGraveCover", Vector3(0, 1.25, -1.65), Vector3(1.5, 2.5, 0.7))
	cover.add_to_group("hide_objects")
	player = load("res://scenes/actors/Player.tscn").instantiate()
	player.camera.position = Vector3(0.03, 0.73, -0.02)
	player.camera.rotation = Vector3(0.08, 0.015, 0.01)
	player.current_level_number = 2 # No passive healing masks health regressions.
	player.position = Vector3(0, 0.86, 0)
	world.add_child(player)
	await wait_seconds(0.1)
	check(player.camera.position.is_equal_approx(Vector3(0.03, 0.73, -0.02)), "Inspector camera offset survives ready and physics")
	check(player.camera.rotation.is_equal_approx(Vector3(0.08, 0.015, 0.01)), "Inspector camera orientation survives ready and physics")
	check(player.camera.get_parent() == player, "Original camera path and ray hierarchy remain available")
	await face_cover()
	check(player.is_on_floor(), "Real capsule settles on physical floor")
	check(player._get_hiding_cover_target() == cover, "Original ray detects physical cover")
	var starting_camera := player.camera.position
	var standing_health := player.current_health
	press_hide()
	check(player.is_hiding and player.is_hidden, "E enters same logical hiding state")
	check(is_equal_approx(player._breath_time_remaining, 5.0), "Original five second breath duration remains")
	check(player.camera.position.distance_to(starting_camera) < 0.005, "Entry does not snap camera to lowered posture")
	check(player.get_node("CollisionShape3D").disabled, "Original collision disabling applies during cover approach")
	await wait_seconds(0.55)
	check(not player._cover_transition_active, "Original cover approach completes")
	check(player.hiding_animation.current_animation == "hide_hold", "Entry settles into authored held breath loop")
	check(player.camera.position.y < starting_camera.y - 0.25, "Visual posture smoothly lowers behind cover")
	check(player.camera.rotation.z < -0.02, "Authored lean is visible after settling")
	check(player.global_position.z < -1.0 and player.global_position.z > -1.3, "Only original approach tween moves the physical body")
	player.take_damage(1)
	check(player.current_health == standing_health, "Original immunity while manually hiding remains")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(8, -10)
	var pitch_before := player._pitch
	player._unhandled_input(mouse)
	check(player._pitch > pitch_before, "Mouse look remains responsive while hiding")
	check(is_equal_approx(player.camera.rotation.x, player._pitch + player.hiding_motion.rotation.x), "Look angle composes with hiding animation")
	player._shake_camera()
	await wait_seconds(0.25)
	check(player.camera_shake.position.length() < 0.0001, "Damage shake returns its independent layer to rest")
	check(player._hiding_camera_weight > 0.999 and player.camera.position.y < 0.3, "Damage shake does not reset hidden posture")
	paused = true
	var paused_breath := player._breath_time_remaining
	var paused_motion := player.hiding_motion.transform
	await wait_seconds(0.2)
	check(is_equal_approx(player._breath_time_remaining, paused_breath), "Pause does not consume breath")
	check(player.hiding_motion.transform.is_equal_approx(paused_motion), "Pause freezes held breath animation")
	paused = false
	player.set_hidden(true)
	press_hide()
	check(not player.is_hiding and player.is_hidden, "Manual exit preserves original transition protection")
	check(player._hiding_state_payload().hidden_by_zone, "Exit payload retains overlapping hide zone")
	await wait_seconds(0.45)
	check(player.is_hidden and not player.is_hiding, "Zone remains hidden after manual exit finishes")
	check(not player.get_node("CollisionShape3D").disabled, "Exit restores collider")
	check(is_equal_approx(player._hiding_camera_weight, 0.0), "Exit restores standing weight")
	check(player.hiding_motion.position.length() < 0.0001 and player.hiding_motion.rotation.length() < 0.0001, "Exit settles all authored animation offsets exactly")
	check(player.camera.position.is_equal_approx(starting_camera), "Exit restores inspector camera position exactly")
	check(is_equal_approx(player.camera.rotation.x, player._pitch), "Exit preserves player look pitch")
	player.set_hidden(false)
	check(not player._hiding_state_payload().hidden, "Leaving final zone removes hidden state")
	# Interrupt entry with another E after the original short physical approach.
	await face_cover()
	press_hide()
	await wait_seconds(0.19)
	var midway_position := player.camera.position
	press_hide()
	check(not player.is_hiding, "E interrupts visual entry after original approach window")
	check(player.camera.position.distance_to(midway_position) < 0.01, "Interrupted entry starts exit without a camera snap")
	await wait_seconds(0.45)
	check(player.hiding_motion.rotation.length() < 0.0001, "Interrupted animation fully clears roll and pitch")
	# Movement still exits, rather than allowing movement while hidden.
	await face_cover()
	press_hide()
	await wait_seconds(0.2)
	Input.action_press("move_back")
	await physics_frame
	await physics_frame
	Input.action_release("move_back")
	check(not player.is_hiding, "Original WASD movement exits hiding")
	await wait_seconds(0.45)
	# Natural timeout, not an artificial end call, retains the five second rule.
	await face_cover()
	press_hide()
	await wait_seconds(4.8)
	check(player.is_hiding and player._breath_time_remaining > 0.0, "Hiding persists until five seconds have elapsed")
	await wait_seconds(0.7)
	check(not player.is_hiding and not player.is_hidden, "Breath expiration exits and finishes original cover transition")
	check(player.current_health == standing_health, "Visual animation never changes health")
	check(player.hiding_motion.transform.is_equal_approx(Transform3D.IDENTITY), "Repeated entries and timeout leave no accumulated visual offset")
	check(not player._hiding_overlay_layer.visible, "Exit animation fades then hides the overlay")
	check(player._is_cover_position_clear(player.global_position), "Restored capsule is outside physical cover")
	world.free()
	print("HIDING_ANIMATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

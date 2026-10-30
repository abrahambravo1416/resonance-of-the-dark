extends SceneTree
var checks := 0
var failures: Array[String] = []
var hud: Node
var player: CharacterBody3D
var world: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); push_error(text)
func touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.index = index; event.position = position; event.pressed = pressed
	Input.parse_input_event(event)
func drag(index: int, position: Vector2, relative := Vector2.ZERO) -> void:
	var event := InputEventScreenDrag.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.index = index; event.position = position; event.relative = relative
	Input.parse_input_event(event)
func wait_frames(count: int) -> void:
	for i in count: await physics_frame
func phase(_text: String) -> void:
	pass
func run() -> void:
	root.size = Vector2i(1280,720)
	root.get_node("GameplayLog").enabled = false
	hud = root.get_node("TouchHUD")
	hud.debug_on_pc = true
	world = Node3D.new(); root.add_child(world); current_scene = world
	if OS.get_environment("RESONANCE_MOBILE_VIDEO") == "1":
		var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-55,-20,0); world.add_child(light)
		var visual := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size=Vector3(30,1,30); visual.mesh=mesh; visual.position.y=-0.5
		var material := StandardMaterial3D.new(); material.albedo_color=Color(0.16,0.28,0.24); visual.material_override=material; world.add_child(visual)
		for i in range(10):
			var post := MeshInstance3D.new(); var post_mesh := BoxMesh.new(); post_mesh.size=Vector3(0.2,2,0.2); post.mesh=post_mesh; post.position=Vector3(i*3-13,1,-6); world.add_child(post)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = Vector3(30, 1, 30); collision.shape = shape
	floor_body.position.y = -0.5; floor_body.add_child(collision); world.add_child(floor_body)
	player = load("res://scenes/actors/Player.tscn").instantiate()
	player.position = Vector3(0,0.86,0); world.add_child(player)
	await wait_frames(12)
	check(hud.controls.visible, "Debug touch controls visible")
	check(player.is_on_floor(), "Real player on physical floor")
	var stick: Control = hud.joystick
	var center: Vector2 = stick.global_position + stick.center_position
	touch(0,center,true); drag(0,center+Vector2(5,0))
	check(Input.get_action_strength("move_right") == 0, "Dead zone suppresses small movement")
	drag(0,center+Vector2(100,0))
	await wait_frames(3)
	check(Input.is_action_pressed("move_right"), "Touch joystick publishes movement")
	var jump_point: Vector2 = hud.controls.position + hud.get_node("TouchControls/Jump").position
	touch(1,jump_point,true)
	# At 30 rendered FPS input is flushed after two physics ticks.
	await wait_frames(4)
	check(player.velocity.y > 0, "Second finger jumps through buffer")
	check(stick.touch_index == 0 and Input.is_action_pressed("move_right"), "Jump does not release movement finger")
	touch(1,jump_point,false)
	check(stick.touch_index == 0, "Other finger release cannot release joystick")
	touch(0,center+Vector2(450,0),false)
	await wait_frames(2)
	check(not Input.is_action_pressed("move_right") and stick.offset == Vector2.ZERO, "Release outside control clears motion")
	await wait_frames(75)
	phase("BUFFER · Tocar salto antes de aterrizar conserva la orden (150 ms)")
	if OS.get_environment("RESONANCE_MOBILE_VIDEO") == "1": await wait_frames(90)
	# A touch just before landing queues the same buffered jump.
	player.position = Vector3(0, 1.0, 0); player.velocity = Vector3(0,-3,0)
	await wait_frames(1)
	touch(1,jump_point,true); touch(1,jump_point,false)
	await wait_frames(6)
	check(player.velocity.y > 0, "Touch input buffer executes on landing")
	await wait_frames(75)
	phase("COYOTE · Saltar después de abandonar el borde (150 ms)")
	if OS.get_environment("RESONANCE_MOBILE_VIDEO") == "1": await wait_frames(90)
	# Leave a real platform edge, then touch during the grace interval.
	player.position = Vector3(14.95,0.86,0); player.velocity = Vector3.ZERO
	await wait_frames(6)
	player.position.x = 15.5
	await wait_frames(2)
	check(not player.is_on_floor() and player.coyote_timer > 0, "Player leaves platform inside coyote window")
	touch(1,jump_point,true)
	await wait_frames(2)
	check(player.velocity.y > 0, "Touch jump consumes coyote window")
	touch(1,jump_point,false)
	player.position = Vector3(0,0.86,0); player.velocity = Vector3.ZERO
	await wait_frames(60)
	var look_point: Vector2 = hud.look.global_position + Vector2(50,50)
	var yaw := player.rotation.y
	touch(2,look_point,true); drag(2,look_point+Vector2(60,0),Vector2(60,0))
	await wait_frames(2); touch(2,look_point,false)
	check(absf(player.rotation.y - yaw) > 0.01,"Touch drag rotates first person camera through Input Map")
	var keyboard := InputEventKey.new(); keyboard.physical_keycode = KEY_D; keyboard.pressed = true; Input.parse_input_event(keyboard)
	touch(0,center,true); drag(0,center+Vector2(80,0)); touch(0,center,false)
	await wait_frames(2)
	check(Input.is_action_pressed("move_right"),"Releasing touch retains held keyboard movement")
	keyboard.pressed=false; Input.parse_input_event(keyboard); await wait_frames(2)
	check(not Input.is_action_pressed("move_right"),"Releasing both sources clears movement")
	var safe: Rect2 = hud.calculate_safe_rect(Vector2(1280,720),Rect2(60,0,2280,1080),Rect2(0,0,2400,1080))
	check(is_equal_approx(safe.position.x,32) and safe.end.x <1280,"Safe area maps physical notch pixels to viewport")
	hud.open_settings(); await wait_frames(2)
	check(paused and hud.settings_panel.visible and not hud.controls.visible,"Settings pause game and release touch")
	hud.close_settings(); await wait_frames(2)
	check(not paused,"Settings restore previous pause state")
	var health: int = player.current_health
	player.take_damage(1)
	check(player.current_health == health-1 and player.shake_strength > 0,"Damage and screenshake retained")

	# Contextual touch reaches the original hiding mechanic.
	player.orient_toward(Vector3(0,0.86,-2)); player.position = Vector3(0,0.86,0); player.velocity=Vector3.ZERO
	var cover := StaticBody3D.new(); cover.position=Vector3(0,1.25,-1.65)
	var cover_collision := CollisionShape3D.new(); var cover_shape := BoxShape3D.new(); cover_shape.size=Vector3(1.5,2.5,0.7)
	cover_collision.shape=cover_shape; cover.add_child(cover_collision); cover.add_to_group("hide_objects"); world.add_child(cover)
	await wait_frames(12)
	check(hud.interaction.visible and hud.interaction.action == "hide_interact", "Context button selects real cover")
	var interact_point: Vector2 = hud.controls.position + hud.interaction.position
	touch(3,interact_point,true); await wait_frames(2); touch(3,interact_point,false)
	check(player.is_hiding, "Contextual touch enters hiding")
	await wait_frames(15)
	touch(3,interact_point,true); await wait_frames(2); touch(3,interact_point,false)
	await wait_frames(25)
	check(not player.is_hiding, "Contextual touch exits hiding")
	var pause_menu: Node = load("res://scenes/ui/PauseMenu.tscn").instantiate(); world.add_child(pause_menu)
	var pause_point: Vector2 = hud.controls.position + hud.get_node("TouchControls/Pause").position
	touch(4,pause_point,true); await wait_frames(2); touch(4,pause_point,false)
	check(paused, "Touch pause reaches existing pause menu")
	pause_menu._resume_game(); await wait_frames(2)
	check(not paused, "Existing pause resume restores controls")
	var radar: Control = player.get_node("ThreatRadarLayer/ThreatRadarHUD")
	hud.debug_on_pc = false
	await wait_frames(4)
	check(not hud.controls.visible and radar.scale == Vector2.ONE, "Disabling touch restores PC radar")
	hud.debug_on_pc = true
	await wait_frames(4)
	var config := root.get_node("ControlSettings")
	config.settings_path = OS.get_environment("RESONANCE_CONTROL_CONFIG") if not OS.get_environment("RESONANCE_CONTROL_CONFIG").is_empty() else "user://mobile_test_controls.cfg"
	config.opacity=0.61; config.control_scale=1.1; config.dead_zone=0.23; config.vibration=false; config.save()
	var saved := ConfigFile.new()
	check(saved.load(config.settings_path)==OK and is_equal_approx(saved.get_value("touch","opacity"),0.61) and not saved.get_value("touch","vibration"), "Settings persist independently of campaign saves")
	var manager := root.get_node("GameManager")
	manager.set_level_progress(2,{"items_collected":2}); manager.total_score=200
	var snapshot: Dictionary = manager.make_campaign_snapshot(2)
	manager.restore_campaign({"save_data":snapshot},1)
	check(manager.get_level_progress(2).items_collected==2 and manager.total_score==200,"Campaign progress round trip retained")
	check(manager.check_and_update_high_score() and manager.high_score==200,"High score calculation retained")
	print("MOBILE_CONTROLS: %d checks, %d failures" % [checks,failures.size()])
	world.free(); current_scene = null; await process_frame
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

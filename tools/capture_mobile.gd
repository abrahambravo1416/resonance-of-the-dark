extends "res://tests/mobile_controls.gd"
## Reproducible demonstration: real touch indices in Godot; not an Android recording.
var caption: Label
var capture_dir := OS.get_environment("RESONANCE_CAPTURE_DIR") if not OS.get_environment("RESONANCE_CAPTURE_DIR").is_empty() else OS.get_user_data_dir().path_join("mobile_captures")
func _initialize() -> void: call_deferred("demo")
func phase(text: String) -> void:
	caption.text = text
func check(value: bool, text: String) -> void:
	super.check(value,text)
	if is_instance_valid(caption): caption.text = ("OK · " if value else "FALLO · ") + text
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.get_texture().get_image().save_png(capture_dir.path_join(name+".png"))
func demo() -> void:
	root.size=Vector2i(1280,720)
	root.get_node("GameplayLog").enabled=false
	root.get_node("GameManager").skip_next_intro=true
	hud=root.get_node("TouchHUD"); hud.debug_on_pc=true
	change_scene_to_file("res://scenes/Level_01.tscn")
	await wait_frames(20)
	for enemy in get_nodes_in_group("enemy"): enemy.set_physics_process(false)
	var overlay:=CanvasLayer.new(); overlay.layer=120; root.add_child(overlay)
	caption=Label.new(); caption.position=Vector2(265,155); caption.size=Vector2(760,60)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",20)
	caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x",2); caption.add_theme_constant_override("shadow_offset_y",2)
	overlay.add_child(caption)
	caption.text="PRÁCTICA 6 · Toques emulados en PC\nJoystick + cámara + botones independientes"
	await wait_frames(120); await capture("controles")
	var c: Vector2=hud.joystick.global_position+hud.joystick.center_position
	var j: Vector2=hud.controls.position+hud.get_node("TouchControls/Jump").position
	caption.text="MULTITOUCH · Dedo 0: movimiento | Dedo 1: salto"
	touch(0,c,true); drag(0,c+Vector2(0,-75)); await wait_frames(20)
	touch(1,j,true); await wait_frames(12); touch(1,j,false); await wait_frames(35)
	touch(0,c,false)
	var l: Vector2=hud.look.global_position+Vector2(80,80)
	caption.text="CÁMARA · Desliza el pulgar derecho en la zona central derecha"
	touch(2,l,true)
	for i in range(20):
		drag(2,l+Vector2(i*4,0),Vector2(4,0)); await wait_frames(1)
	touch(2,l,false); await wait_frames(120); await capture("hud-movil")
	hud.open_settings(); caption.position.y = 680; caption.text="AJUSTES GUARDADOS · Tamaño, opacidad, zona muerta y vibración"
	await wait_frames(150); await capture("ajustes"); hud.close_settings(); caption.position.y = 155
	await wait_frames(15)
	current_scene.free(); current_scene=null; await wait_frames(3)
	caption.text="VERIFICACIÓN · Buffer y coyote con las mismas acciones táctiles"
	# A visible physical test platform makes takeoff and landing readable.
	await run()

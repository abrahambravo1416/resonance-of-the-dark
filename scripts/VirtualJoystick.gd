extends Control
## Palanca fija: cada dedo pertenece a su control hasta soltarlo, incluso fuera del área.
@export var joystick_radius: float = 100.0
@export var dead_zone: float = 0.2
var touch_index: int = -1
var center_position: Vector2
var offset := Vector2.ZERO
var output := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility)
	_layout()

func _layout() -> void:
	center_position = size * 0.5
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1 and event.position.distance_to(center_position) <= joystick_radius:
			touch_index = event.index
			_update_offset(event.position)
			accept_event()
		elif not event.pressed and event.index == touch_index:
			release_touch()
			accept_event()
	elif event is InputEventScreenDrag and event.index == touch_index:
		_update_offset(event.position)
		accept_event()

func _input(event: InputEvent) -> void:
	# GUI focus need not follow a finger that leaves the joystick rectangle.
	if touch_index < 0:
		return
	if event is InputEventScreenTouch and event.index == touch_index and (not event.pressed or event.canceled):
		release_touch()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_index:
		_update_offset(get_global_transform_with_canvas().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()

func _update_offset(point: Vector2) -> void:
	offset = (point - center_position).limit_length(maxf(joystick_radius, 1.0))
	output = offset / maxf(joystick_radius, 1.0)
	if output.length() < dead_zone:
		output = Vector2.ZERO
	_apply_axis("move_right", maxf(0.0, output.x))
	_apply_axis("move_left", maxf(0.0, -output.x))
	_apply_axis("move_back", maxf(0.0, output.y))
	_apply_axis("move_forward", maxf(0.0, -output.y))
	queue_redraw()

func _apply_axis(action: String, strength: float) -> void:
	var router := get_node_or_null("/root/UnifiedInput")
	if router != null:
		router.set_virtual("joystick", action, strength)
	elif strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func release_touch() -> void:
	touch_index = -1
	offset = Vector2.ZERO
	output = Vector2.ZERO
	for action in ["move_right", "move_left", "move_forward", "move_back"]:
		_apply_axis(action, 0.0)
	queue_redraw()

func _on_visibility() -> void:
	if not is_visible_in_tree():
		release_touch()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_touch()

func _exit_tree() -> void:
	release_touch()

func _draw() -> void:
	draw_circle(center_position, joystick_radius, Color(0.03, 0.08, 0.09, 0.8))
	draw_arc(center_position, joystick_radius - 2, 0, TAU, 64, Color("97bfb0"), 3, true)
	draw_arc(center_position, joystick_radius * dead_zone, 0, TAU, 40, Color(0.6, 0.8, 0.7, 0.35), 1, true)
	draw_circle(center_position + offset, joystick_radius * 0.34, Color("b8d5c1"))

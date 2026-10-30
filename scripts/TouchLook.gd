extends Control
var touch_index: int = -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and touch_index == -1:
		touch_index = event.index
		accept_event()

func _input(event: InputEvent) -> void:
	if touch_index < 0: return
	if event is InputEventScreenTouch and event.index == touch_index and (not event.pressed or event.canceled):
		touch_index = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_index:
		get_node("/root/UnifiedInput").look_delta += event.relative
		get_viewport().set_input_as_handled()

func release_touch() -> void:
	touch_index = -1

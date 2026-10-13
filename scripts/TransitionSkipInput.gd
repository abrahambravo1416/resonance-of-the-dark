extends Node

signal skip_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_accept"):
		skip_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
			skip_requested.emit()
			get_viewport().set_input_as_handled()

extends Node

signal skip_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	var skip_button := get_parent().get_node_or_null("Level2Announcement/Content/SkipMenuButton") as Button
	if skip_button != null:
		skip_button.pressed.connect(_emit_skip_requested)


func _emit_skip_requested() -> void:
	skip_requested.emit()


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

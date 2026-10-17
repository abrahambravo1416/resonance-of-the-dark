extends Node3D

@export var interaction_key: Key = KEY_G
@export var dialogue_seconds: float = 8.0
@export var greeting: String = "Una voz aguarda cerca de la entrada. G para escucharla (opcional)."

@onready var hint: Label = $NarrativeHUD/Hint
@onready var panel: PanelContainer = $NarrativeHUD/Dialogue
@onready var speaker: Label = $NarrativeHUD/Dialogue/Margin/Content/Speaker
@onready var dialogue: Label = $NarrativeHUD/Dialogue/Margin/Content/Words
@onready var dismiss: Label = $NarrativeHUD/Dialogue/Margin/Content/Dismiss

var _nearest: Node3D
var _remaining: float = 0.0
var _greeted: bool = false


func _ready() -> void:
	panel.hide()
	hint.hide()
	add_to_group("narrative_layers")


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if bool(player.get("controls_frozen")) or bool(player.get("is_dead")):
		hint.hide()
		return
	if not _greeted:
		_greeted = true
		show_message("Ecos del cementerio", greeting, 6.0)
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining == 0.0:
		panel.hide()
	_nearest = null
	var nearest_distance := INF
	for point in get_tree().get_nodes_in_group("narrative_points"):
		if bool(point.get("collected")):
			continue
		var distance := player.global_position.distance_to(point.global_position)
		var point_marker: Label3D = point.get("marker")
		if point_marker != null:
			point_marker.visible = distance < float(point.get("interaction_distance")) + 0.8
		if distance <= float(point.get("interaction_distance")) and distance < nearest_distance:
			nearest_distance = distance
			_nearest = point
	hint.visible = _nearest != null
	if _nearest != null:
		hint.text = "%s · %s %s" % [OS.get_keycode_string(interaction_key), "Recordar" if _nearest.encounter_type == "memory" else "Escuchar a", _nearest.display_name]


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode != interaction_key or _nearest == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or bool(player.get("controls_frozen")) or bool(player.get("is_dead")):
		return
	var point := _nearest
	var words: String = point.interact_narrative(player)
	if not words.is_empty():
		show_message(point.display_name, words, dialogue_seconds)
	get_viewport().set_input_as_handled()


func show_message(who: String, words: String, duration: float = 6.0) -> void:
	speaker.text = who.to_upper()
	dialogue.text = words
	dismiss.text = "Puedes seguir caminando · encuentro opcional"
	_remaining = duration
	panel.show()

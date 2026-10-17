extends Area3D
## Solo sonido, luz decorativa y relato. No altera las reglas de la partida.

@export var event_id: String = "whisper"
@export var title: String = "Un eco entre las lápidas"
@export_multiline var message: String = "Por un instante, alguien camina al otro lado del muro."
@export var once_per_attempt: bool = true
@export var audio: AudioStreamPlayer3D
@export var light: OmniLight3D
@export var animation: AnimationPlayer
var triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or (triggered and once_per_attempt):
		return
	triggered = true
	if audio != null:
		audio.play()
	if animation != null and animation.has_animation("echo"):
		animation.play("echo")
	var layer := get_tree().get_first_node_in_group("narrative_layers")
	if layer != null:
		layer.show_message(title, message)
	var logger := get_node_or_null("/root/GameplayLog")
	if logger != null:
		logger.record("ambient_event", {"id": event_id, "name": title, "message": message}, body.global_position)

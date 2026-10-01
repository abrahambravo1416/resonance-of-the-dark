extends Area3D
class_name HidingZone

@export var trigger_size: Vector3 = Vector3(2.4, 2.0, 2.4)

var _occupants: Dictionary[int, Node3D] = {}


func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = trigger_size
		collision.shape = box
		add_child(collision)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_occupants[body.get_instance_id()] = body
	_set_player_hidden(body, true)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_occupants.erase(body.get_instance_id())
	_set_player_hidden(body, false)


func _set_player_hidden(player: Node3D, hidden: bool) -> void:
	if player.has_method("set_hidden"):
		player.set_hidden(hidden)
	else:
		player.set("is_hidden", hidden)

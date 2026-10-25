extends Area3D
class_name InteractableItem

enum ItemType { CAULDRON, POTION, PUMPKIN, SPELLBOOK }

@export var item_name: String = "Collectible"
@export var item_type: ItemType = ItemType.CAULDRON
@export var pickup_sound: AudioStream
@export var pickup_particles: PackedScene

var _collected: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = true
	if get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = 0.55
		collision.shape = sphere
		add_child(collision)


func interact(player: PlayerController) -> void:
	if _collected or not is_instance_valid(player) or not player.has_method("collect_item"):
		return
	_collected = true
	player.collect_item(item_name, str(name))
	_play_feedback()
	queue_free()


func _play_feedback() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if pickup_sound != null:
		var audio := AudioStreamPlayer3D.new()
		audio.stream = pickup_sound
		audio.global_position = global_position
		scene.add_child(audio)
		audio.finished.connect(audio.queue_free)
		audio.play()
	if pickup_particles != null:
		var effect := pickup_particles.instantiate()
		scene.add_child(effect)
		if effect is Node3D:
			effect.global_position = global_position
		if effect is GPUParticles3D:
			effect.emitting = true
		elif effect is CPUParticles3D:
			effect.emitting = true

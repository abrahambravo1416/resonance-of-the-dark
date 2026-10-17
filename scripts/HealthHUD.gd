extends CanvasLayer

const HEALTH_BLOCK_COUNT := 4
@export var active_color := Color("d94a3d")
@export var empty_color := Color("342c3a")

var _blocks: Array[ColorRect] = []
var _player: Node


func _ready() -> void:
	_build_interface()
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var callback := Callable(self, "_on_health_changed")
	if _player.has_signal("health_changed") and not _player.is_connected("health_changed", callback):
		_player.connect("health_changed", callback)
	_on_health_changed(int(_player.get("current_health")), int(_player.get("max_health")))


func _build_interface() -> void:
	_blocks.clear()
	for frame in $HealthHUD/HealthContainer/HealthBlocks.get_children():
		var fill := frame.get_node_or_null("Fill") as ColorRect
		if fill != null:
			_blocks.append(fill)


func _on_health_changed(current_health: int, max_health: int) -> void:
	var visible_blocks := clampi(current_health, 0, mini(max_health, HEALTH_BLOCK_COUNT))
	for index in _blocks.size():
		_blocks[index].color = active_color if index < visible_blocks else empty_color
		_blocks[index].modulate.a = 1.0 if index < visible_blocks else 0.55

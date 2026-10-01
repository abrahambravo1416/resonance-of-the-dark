extends Node3D
class_name LevelBuilder

## Runtime level generator. Attach this script to a level root named Level_01,
## or call build_map() from another script after placing it in the scene.

@export_group("Generation")
@export var auto_build_on_ready: bool = true
@export var grid_size: Vector2i = Vector2i(10, 10)
@export_range(1.0, 20.0, 0.25) var cell_size: float = 3.0
@export_range(0.0, 0.8, 0.05) var obstacle_density: float = 0.3
@export_range(0.0, 1.0, 0.05) var decoration_density: float = 0.6
@export_range(0, 8, 1) var open_grave_count: int = 2
@export_range(0.4, 1.5, 0.05) var open_grave_depth: float = 0.8
@export var random_seed: int = 0

@export_group("Assets")
@export var obstacle_scenes: Array[PackedScene] = []
@export var collectible_scenes: Array[PackedScene] = []
@export var hiding_scenes: Array[PackedScene] = []
@export var collectible_count: int = 4
@export var hiding_zone_count: int = 3

@export_group("Navigation")
@export var bake_navigation_after_build: bool = true
@export var navigation_agent_radius: float = 0.3
@export var navigation_agent_height: float = 2.0

const OBSTACLE_ASSET_PATHS: Array[String] = [
	"res://assets/halloween/gltf/gravestone.gltf",
	"res://assets/halloween/gltf/fence.gltf",
	"res://assets/halloween/gltf/tree_dead_medium.gltf",
	"res://assets/halloween/gltf/grave_A.gltf",
]
const HIDING_ASSET_PATHS: Array[String] = [
	"res://assets/halloween/gltf/crypt.gltf",
	"res://assets/halloween/gltf/coffin_decorated.gltf",
]
const PUMPKIN_ASSET_PATH: String = "res://assets/halloween/gltf/pumpkin_orange_jackolantern.gltf"
const OPEN_GRAVE_ASSET_PATH: String = "res://assets/halloween/gltf/floor_dirt_grave.gltf"
const FLOOR_DIRT_ASSET_PATH: String = "res://assets/halloween/gltf/floor_dirt.gltf"
const HALLOWEEN_GLTF_PATH: String = "res://assets/halloween/gltf"
const ENEMY_MODEL_KEYWORDS: Array[String] = ["enemy", "skeleton", "ghost", "zombie", "monster", "creature", "undead"]
const DECORATION_KEYWORDS: Array[String] = [
	"gravestone", "gravemarker", "grave_", "tree_", "fence", "candle", "lantern", "bone_", "ribcage", "skull",
	"pumpkin", "shrine", "plaque", "post_", "pillar", "bench", "broken", "destroyed", "arch", "gate",
	"coffin", "sarcophagus", "crypt", "cauldron", "book", "post", "wall",
]
const ENEMY_BODY_PART_ASSETS: Array[String] = [
	"res://assets/halloween/gltf/ribcage.gltf",
	"res://assets/halloween/gltf/bone_A.gltf",
	"res://assets/halloween/gltf/bone_B.gltf",
	"res://assets/halloween/gltf/bone_C.gltf",
]
const ENEMY_PUMPKIN_HEAD_ASSETS: Array[String] = [
	"res://assets/halloween/gltf/pumpkin_orange_jackolantern.gltf",
	"res://assets/halloween/gltf/pumpkin_yellow_jackolantern.gltf",
	"res://assets/halloween/gltf/pumpkin_orange.gltf",
]
const ITEM_NAMES: Array[String] = ["Cauldron", "Potion", "Pumpkin", "Spellbook"]
const ITEM_TYPES: Array[InteractableItem.ItemType] = [
	InteractableItem.ItemType.CAULDRON,
	InteractableItem.ItemType.POTION,
	InteractableItem.ItemType.PUMPKIN,
	InteractableItem.ItemType.SPELLBOOK,
]

var navigation_region: NavigationRegion3D
var environment_root: Node3D
var hiding_zones_root: Node3D
var items_root: Node3D
var patrol_points_root: Node3D
var player: CharacterBody3D
var enemy: CharacterBody3D
var _patrol_markers: Array[Node3D] = []
var _halloween_scenes: Array[PackedScene] = []
var _decoration_scenes: Array[PackedScene] = []
var _path_tile_scenes: Array[PackedScene] = []

var _rng := RandomNumberGenerator.new()
var _blocked_cells: Dictionary[Vector2i, bool] = {}
var _free_cells: Array[Vector2i] = []
var _open_grave_cells: Array[Vector2i] = []


func _ready() -> void:
	if auto_build_on_ready:
		build_map()


func build_map() -> void:
	grid_size.x = maxi(3, grid_size.x)
	grid_size.y = maxi(3, grid_size.y)
	_rng.seed = random_seed if random_seed != 0 else int(Time.get_unix_time_from_system() * 1000.0)
	_autofill_asset_lists()
	_resolve_level_nodes()
	_clear_children(environment_root)
	_clear_children(hiding_zones_root)
	_clear_children(items_root)
	_clear_children(patrol_points_root)
	_blocked_cells.clear()
	_free_cells.clear()
	_open_grave_cells.clear()
	_patrol_markers.clear()
	_build_floor_and_maze()
	_spawn_perimeter_fences()
	_ensure_player_and_enemy()
	_place_player_and_enemy()
	spawn_hiding_zones()
	_spawn_open_graves()
	spawn_collectibles()
	_spawn_passage_decorations()
	generate_patrol_points()
	if bake_navigation_after_build:
		bake_navigation()
	else:
		_activate_enemy_navigation()


func _load_assets_from_dir(path: String) -> Array[PackedScene]:
	var asset_paths: Array[String] = []
	_collect_asset_paths(path, asset_paths)
	asset_paths.sort()
	var scenes: Array[PackedScene] = []
	for asset_path in asset_paths:
		var packed_scene := ResourceLoader.load(asset_path) as PackedScene
		if packed_scene != null:
			scenes.append(packed_scene)
	return scenes


func _collect_asset_paths(path: String, asset_paths: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		push_warning("No se pudo leer el directorio de assets: %s" % path)
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if file_name != "." and file_name != "..":
			var entry_path := path.path_join(file_name)
			if directory.current_is_dir():
				_collect_asset_paths(entry_path, asset_paths)
			elif file_name.get_extension().to_lower() in ["glb", "gltf", "tscn"]:
				asset_paths.append(entry_path)
		file_name = directory.get_next()
	directory.list_dir_end()


func _autofill_asset_lists() -> void:
	if _halloween_scenes.is_empty():
		_halloween_scenes = _load_assets_from_dir(HALLOWEEN_GLTF_PATH)
	var fill_hiding_scenes := hiding_scenes.is_empty()
	var fill_collectible_scenes := collectible_scenes.is_empty()
	var fill_obstacle_scenes := obstacle_scenes.is_empty()
	for scene in _halloween_scenes:
		var asset_name := scene.resource_path.get_file().get_basename().to_lower()
		if _is_path_tile_asset(asset_name) and not _path_tile_scenes.has(scene):
			_path_tile_scenes.append(scene)
		if not _is_hanging_lantern_asset(asset_name) and _is_decoration_asset(asset_name) and not _decoration_scenes.has(scene):
			_decoration_scenes.append(scene)
		var is_hiding_asset := _is_hiding_asset(asset_name)
		var is_collectible_asset := _is_collectible_asset(asset_name)
		if fill_hiding_scenes and is_hiding_asset:
			hiding_scenes.append(scene)
		elif fill_collectible_scenes and is_collectible_asset:
			collectible_scenes.append(scene)
		elif fill_obstacle_scenes and not is_hiding_asset and not is_collectible_asset and _is_blocking_asset(asset_name):
			obstacle_scenes.append(scene)


func _is_hiding_asset(asset_name: String) -> bool:
	for keyword in ["crypt", "sarcophagus", "coffin", "tombstone", "gravestone", "gravemarker", "tomb"]:
		if asset_name.contains(keyword):
			return true
	return false


func _is_collectible_asset(asset_name: String) -> bool:
	for keyword in ["pumpkin", "cauldron", "potion", "phial", "vial", "elixir", "spellbook", "spell_book", "spell-book", "book", "grimoire", "spell", "magic", "witch", "rune", "crystal"]:
		if asset_name.contains(keyword):
			return true
	return false


func _is_path_tile_asset(asset_name: String) -> bool:
	for keyword in ["dirt_path", "pavement", "path_tile", "stepping_stones", "path_"]:
		if asset_name.contains(keyword):
			return true
	return false


func _is_hanging_lantern_asset(asset_name: String) -> bool:
	return asset_name.contains("lantern_hanging") or asset_name.contains("hanging_lantern")


func _is_blocking_asset(asset_name: String) -> bool:
	for keyword in ["tree_", "fence", "wall", "grave_", "gravestone", "gravemarker", "pillar", "arch"]:
		if asset_name.contains(keyword):
			return true
	return false


func _is_decoration_asset(asset_name: String) -> bool:
	for keyword in DECORATION_KEYWORDS:
		if asset_name.contains(keyword):
			return true
	return false


func _resolve_level_nodes() -> void:
	_ensure_lighting()
	navigation_region = get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if navigation_region == null:
		navigation_region = NavigationRegion3D.new()
		navigation_region.name = "NavigationRegion3D"
		add_child(navigation_region)

	environment_root = _ensure_container(navigation_region, "Environment")
	hiding_zones_root = _ensure_container(navigation_region, "HidingZones")
	items_root = _ensure_container(navigation_region, "Items")
	patrol_points_root = _ensure_container(self, "PatrolPoints")

	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()
	navigation_region.navigation_mesh.agent_radius = navigation_agent_radius
	navigation_region.navigation_mesh.agent_height = maxf(2.0, navigation_agent_height)
	navigation_region.navigation_mesh.agent_max_climb = 0.3
	navigation_region.navigation_mesh.agent_max_slope = 30.0
	navigation_region.navigation_mesh.filter_ledge_spans = true
	navigation_region.navigation_mesh.filter_walkable_low_height_spans = true
	navigation_region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_region.navigation_mesh.geometry_collision_mask = 1
	# Include world geometry placed inside the region, including meshes inside static bodies.
	navigation_region.navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN


func _ensure_lighting() -> void:
	var sun := get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		add_child(sun)
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true

	var world_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_node == null:
		world_node = WorldEnvironment.new()
		world_node.name = "WorldEnvironment"
		add_child(world_node)
	if world_node.environment == null:
		world_node.environment = Environment.new()
	var world_environment := world_node.environment
	world_environment.background_mode = Environment.BG_SKY
	if world_environment.sky == null:
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.025, 0.035, 0.09)
		sky_material.sky_horizon_color = Color(0.25, 0.16, 0.2)
		sky_material.ground_bottom_color = Color(0.025, 0.02, 0.03)
		sky_material.ground_horizon_color = Color(0.16, 0.1, 0.12)
		sky.sky_material = sky_material
		world_environment.sky = sky
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color(0.38, 0.36, 0.33)
	world_environment.ambient_light_energy = 0.65


func _build_floor_and_maze() -> void:
	var center_x := grid_size.x / 2
	var center_z := grid_size.y / 2
	_choose_open_grave_cells()
	_build_ground_base()
	for z in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, z)
			var world_position := _cell_to_world(cell)
			if _open_grave_cells.has(cell):
				continue
			if _is_protected_corridor(cell, center_x, center_z):
				_free_cells.append(cell)
				continue
			if _rng.randf() < obstacle_density:
				_blocked_cells[cell] = true
				_add_obstacle(world_position)
			else:
				_free_cells.append(cell)


func _choose_open_grave_cells() -> void:
	var candidates: Array[Vector2i] = []
	for z in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, z)
			if x > 0 and x < grid_size.x - 1 and z > 0 and z < grid_size.y - 1 \
			and _is_protected_corridor(cell, grid_size.x / 2, grid_size.y / 2) \
			and cell != Vector2i.ZERO \
			and cell != Vector2i(grid_size.x - 1, grid_size.y - 1):
				candidates.append(cell)
	while not candidates.is_empty() and _open_grave_cells.size() < open_grave_count:
		var index := _rng.randi_range(0, candidates.size() - 1)
		_open_grave_cells.append(candidates.pop_at(index))


func _build_ground_base() -> void:
	# Prefer the KayKit textured dirt tile. The generated material mesh remains a
	# fallback for projects where the pack is missing. Only grave cells are cut out.
	var floor_scene := load(FLOOR_DIRT_ASSET_PATH) as PackedScene
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, z)
			if _open_grave_cells.has(cell):
				continue
			if not _path_tile_scenes.is_empty() and _is_path_cell(cell):
				_add_path_tile(cell)
			if floor_scene != null:
				_add_floor_dirt_tile(floor_scene, cell)
				continue
			var x0 := float(x) * cell_size - cell_size * 0.5
			var x1 := x0 + cell_size
			var z0 := float(z) * cell_size - cell_size * 0.5
			var z1 := z0 + cell_size
			var base_index := vertices.size()
			vertices.append_array(PackedVector3Array([
				Vector3(x0, -0.025, z0), Vector3(x0, -0.025, z1),
				Vector3(x1, -0.025, z1), Vector3(x1, -0.025, z0),
			]))
			normals.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
			uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT]))
			indices.append_array(PackedInt32Array([
				base_index, base_index + 1, base_index + 2,
				base_index, base_index + 2, base_index + 3,
			]))

	var ground_mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.18, 0.22, 0.15)
		material.roughness = 0.8
		material.metallic = 0.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		ground_mesh.surface_set_material(0, material)
		var ground_visual := MeshInstance3D.new()
		ground_visual.name = "UnifiedGround"
		ground_visual.mesh = ground_mesh
		ground_visual.material_override = material
		ground_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		environment_root.add_child(ground_visual)

	var ground_collision := StaticBody3D.new()
	ground_collision.name = "GroundCollision"
	ground_collision.collision_layer = 1
	ground_collision.collision_mask = 1
	environment_root.add_child(ground_collision)
	for z in grid_size.y:
		var run_start := -1
		for x in range(grid_size.x + 1):
			var has_floor := x < grid_size.x and not _open_grave_cells.has(Vector2i(x, z))
			if has_floor and run_start < 0:
				run_start = x
			elif not has_floor and run_start >= 0:
				var run_length := x - run_start
				var collision := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(run_length * cell_size, 0.2, cell_size)
				collision.shape = shape
				collision.position = Vector3((float(run_start) + float(run_length - 1) * 0.5) * cell_size, -0.1, float(z) * cell_size)
				ground_collision.add_child(collision)
				run_start = -1


func _add_floor_dirt_tile(scene: PackedScene, cell: Vector2i) -> void:
	var tile := scene.instantiate() as Node3D
	if tile == null:
		return
	tile.name = "DirtFloor_%d_%d" % [cell.x, cell.y]
	environment_root.add_child(tile)
	var bounds := _get_combined_visual_aabb(tile)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001 or bounds.size.z <= 0.001:
		tile.queue_free()
		return
	var tile_scale_x := cell_size / bounds.size.x
	var tile_scale_z := cell_size / bounds.size.z
	var tile_scale_y := 0.06 / bounds.size.y
	tile.scale = Vector3(tile_scale_x, tile_scale_y, tile_scale_z)
	var top_y := (bounds.position.y + bounds.size.y) * tile_scale_y
	tile.position = _cell_to_world(cell) + Vector3.UP * (-0.025 - top_y)


func _add_path_tile(cell: Vector2i) -> void:
	var scene := _path_tile_scenes[_rng.randi_range(0, _path_tile_scenes.size() - 1)]
	var path_visual := scene.instantiate()
	path_visual.name = "PathTile_%d_%d" % [cell.x, cell.y]
	environment_root.add_child(path_visual)
	_strip_embedded_colliders(path_visual)
	if path_visual is Node3D:
		path_visual.position = _cell_to_world(cell)
		path_visual.scale = Vector3.ONE * (cell_size * 0.5)
		_align_visual_base_to_ground(path_visual, 0.0)


func _spawn_open_graves() -> void:
	var grave_scene := load(OPEN_GRAVE_ASSET_PATH) as PackedScene
	if grave_scene == null:
		for scene in _halloween_scenes:
			var asset_name := scene.resource_path.get_file().get_basename().to_lower()
			if asset_name.contains("grave") and asset_name.contains("floor"):
				grave_scene = scene
				break
	for index in _open_grave_cells.size():
		var cell := _open_grave_cells[index]
		var grave_root := Node3D.new()
		grave_root.name = "OpenGrave_%02d" % (index + 1)
		grave_root.position = _cell_to_world(cell)
		environment_root.add_child(grave_root)
		if grave_scene != null:
			var grave_visual := grave_scene.instantiate()
			grave_root.add_child(grave_visual)
			_strip_embedded_colliders(grave_visual)
			if grave_visual is Node3D:
				var source_bounds := _get_combined_visual_aabb(grave_visual)
				var horizontal_scale: float = cell_size / 4.0
				var vertical_scale: float = open_grave_depth / maxf(source_bounds.size.y, 0.001)
				grave_visual.scale = Vector3(horizontal_scale, vertical_scale, horizontal_scale)
				var grave_bounds := _get_combined_visual_aabb(grave_visual)
				# floor_dirt_grave is modeled from y=-1.5 to y=0.03: its top lip
				# stays flush with world y=0 while the mesh extends down into the pit.
				var grave_top_y: float = (grave_bounds.position.y + grave_bounds.size.y) * grave_visual.scale.y
				grave_visual.position.y = -grave_top_y
		_add_grave_pit_floor(cell, index)
		var hiding_zone := HidingZone.new()
		hiding_zone.name = "OpenGraveHidingZone_%02d" % (index + 1)
		hiding_zone.position = _cell_to_world(cell) + Vector3.DOWN * (open_grave_depth * 0.5)
		hiding_zone.trigger_size = Vector3(cell_size * 0.9, open_grave_depth + 0.8, cell_size * 0.9)
		hiding_zones_root.add_child(hiding_zone)


func _add_grave_pit_floor(cell: Vector2i, index: int) -> void:
	var pit_body := StaticBody3D.new()
	pit_body.name = "OpenGravePit_%02d" % (index + 1)
	pit_body.position = _cell_to_world(cell)
	pit_body.collision_layer = 1
	pit_body.collision_mask = 1
	environment_root.add_child(pit_body)
	var pit_collision := CollisionShape3D.new()
	var pit_shape := BoxShape3D.new()
	var floor_thickness := 0.12
	pit_shape.size = Vector3(cell_size, floor_thickness, cell_size)
	pit_collision.shape = pit_shape
	pit_collision.position.y = -open_grave_depth - floor_thickness * 0.5
	pit_body.add_child(pit_collision)


func _is_path_cell(cell: Vector2i) -> bool:
	var center_x := grid_size.x / 2
	var center_z := grid_size.y / 2
	# The center cross forms the maze route; the north/east edge path reaches the entrance.
	return cell.x == center_x or cell.y == center_z or cell.x == 0 or cell.y == 0


func _add_obstacle(world_position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Obstacle_%d_%d" % [roundi(world_position.x / cell_size), roundi(world_position.z / cell_size)]
	body.position = world_position
	body.rotation.y = _rng.randf_range(0.0, TAU)
	body.collision_layer = 1
	body.collision_mask = 1
	environment_root.add_child(body)
	var scene := _pick_scene(obstacle_scenes, _default_obstacle_scenes())
	var asset_name := scene.resource_path.get_file().get_basename().to_lower() if scene != null else ""
	if scene != null:
		var visual := scene.instantiate()
		body.add_child(visual)
		_strip_embedded_colliders(visual)
		if visual is Node3D:
			visual.scale = Vector3.ONE * (_fence_visual_scale(visual) if _is_fence_asset(asset_name) else cell_size / 3.0)
			_align_visual_base_to_ground(visual, 0.0)
		if _is_closed_gate_asset(asset_name):
			_add_closed_gate_collision(body)
			return
		if _is_passable_arch_asset(asset_name):
			_add_arch_pillar_collisions(body)
			return
		if _is_fence_asset(asset_name):
			_add_visual_bounds_collision(body, "FenceCollision", asset_name, 2.2)
			return
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(cell_size * 0.55, 2.0, 0.75)
	collision.shape = shape
	collision.position.y = 1.0
	body.add_child(collision)


func _is_passable_arch_asset(asset_path: String) -> bool:
	var asset_name := asset_path.get_file().get_basename().to_lower()
	return asset_name.contains("arch") and not _is_closed_gate_asset(asset_name)


func _is_closed_gate_asset(asset_name: String) -> bool:
	return asset_name.contains("arch_gate") or asset_name.contains("fence_gate") or asset_name.contains("closed_gate")


func _is_fence_asset(asset_name: String) -> bool:
	return asset_name.contains("fence") or asset_name.contains("wall")


func _fence_visual_scale(visual: Node3D) -> float:
	var bounds := _get_combined_visual_aabb(visual)
	var model_length := maxf(bounds.size.x, bounds.size.z)
	return cell_size / maxf(model_length, 0.001)


func _add_closed_gate_collision(parent: StaticBody3D) -> void:
	# arch_gate/fence_gate contain a closed mesh across the opening. A single
	# conservative collider prevents either CharacterBody3D from slipping through.
	var bounds := _get_combined_visual_aabb(parent)
	if bounds.size == Vector3.ZERO:
		bounds = AABB(Vector3(-cell_size * 0.5, 0.0, -0.2), Vector3(cell_size, 2.4, 0.4))
	var collision := CollisionShape3D.new()
	collision.name = "ClosedGateCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(bounds.size.x, cell_size * 0.7), maxf(bounds.size.y, 2.2), maxf(minf(bounds.size.z, 0.5), 0.25))
	collision.shape = shape
	collision.position = bounds.position + bounds.size * 0.5
	collision.position.y = maxf(collision.position.y, shape.size.y * 0.5)
	parent.add_child(collision)


func _add_arch_pillar_collisions(parent: StaticBody3D) -> void:
	# Two separate supports preserve the central opening for the player and the navmesh.
	var pillar_width := maxf(0.28, cell_size * 0.14)
	var pillar_depth := maxf(0.35, cell_size * 0.2)
	var opening_half_width := cell_size * 0.28
	var pillar_height := maxf(2.35, navigation_agent_height + 0.5)
	for side in [-1.0, 1.0]:
		var collision := CollisionShape3D.new()
		collision.name = "ArchPillarCollision_%s" % ("L" if side < 0.0 else "R")
		var shape := BoxShape3D.new()
		shape.size = Vector3(pillar_width, pillar_height, pillar_depth)
		collision.shape = shape
		collision.position = Vector3(side * (opening_half_width + pillar_width * 0.5), pillar_height * 0.5, 0.0)
		parent.add_child(collision)


func _spawn_perimeter_fences() -> void:
	var fence_scene := _find_fence_scene()
	var left_x := -cell_size * 0.5
	var right_x := (float(grid_size.x) - 0.5) * cell_size
	var near_z := -cell_size * 0.5
	var far_z := (float(grid_size.y) - 0.5) * cell_size
	for z in grid_size.y:
		var segment_z := float(z) * cell_size
		_add_fence_segment("Fence_West_%02d" % z, Vector3(left_x, 0.0, segment_z), true, fence_scene)
		_add_fence_segment("Fence_East_%02d" % z, Vector3(right_x, 0.0, segment_z), true, fence_scene)
	for x in grid_size.x:
		var segment_x := float(x) * cell_size
		_add_fence_segment("Fence_North_%02d" % x, Vector3(segment_x, 0.0, near_z), false, fence_scene)
		_add_fence_segment("Fence_South_%02d" % x, Vector3(segment_x, 0.0, far_z), false, fence_scene)


func _find_fence_scene() -> PackedScene:
	for scene in obstacle_scenes:
		var asset_name := scene.resource_path.get_file().get_basename().to_lower()
		if asset_name == "fence" or asset_name.begins_with("fence_") or asset_name.begins_with("fence-"):
			return scene
	for path in ["res://assets/halloween/gltf/fence.gltf", "res://assets/halloween/gltf/fence_seperate.gltf"]:
		var scene := load(path) as PackedScene
		if scene != null:
			return scene
	return null


func _add_fence_segment(segment_name: String, world_position: Vector3, along_z: bool, fence_scene: PackedScene) -> void:
	var fence_body := StaticBody3D.new()
	fence_body.name = segment_name
	fence_body.position = world_position
	fence_body.collision_layer = 1
	fence_body.collision_mask = 1
	if along_z:
		fence_body.rotation.y = PI * 0.5
	environment_root.add_child(fence_body)
	if fence_scene != null:
		var visual := fence_scene.instantiate()
		fence_body.add_child(visual)
		_strip_embedded_colliders(visual)
		if visual is Node3D:
			visual.scale = Vector3.ONE * _fence_visual_scale(visual)
			_align_visual_base_to_ground(visual, 0.0)
	else:
		_add_procedural_fence_visual(fence_body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(cell_size, 2.2, 0.5)
	collision.shape = shape
	collision.position.y = 1.1
	fence_body.add_child(collision)


func _add_procedural_fence_visual(parent: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.075, 0.045)
	for rail_y in [0.65, 1.5]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(cell_size, 0.12, 0.12)
		rail.mesh = rail_mesh
		rail.position.y = rail_y
		rail.material_override = material
		parent.add_child(rail)
	for post_x in [-cell_size * 0.45, cell_size * 0.45]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.16, 2.0, 0.16)
		post.mesh = post_mesh
		post.position = Vector3(post_x, 1.0, 0.0)
		post.material_override = material
		parent.add_child(post)


func spawn_hiding_zones() -> void:
	if hiding_zones_root == null:
		_resolve_level_nodes()
	_clear_children(hiding_zones_root)
	var cells := _take_random_cells(hiding_zone_count)
	var defaults := _default_hiding_scenes()
	for index in cells.size():
		var cell := cells[index]
		var zone := HidingZone.new()
		zone.name = "HidingZone_%02d" % (index + 1)
		zone.position = _cell_to_world(cell)
		zone.rotation.y = _rng.randf_range(0.0, TAU)
		zone.trigger_size = Vector3(cell_size * 0.8, 2.2, cell_size * 0.8)
		hiding_zones_root.add_child(zone)
		var scene := _pick_scene(hiding_scenes, defaults)
		if scene != null:
			var visual := scene.instantiate()
			zone.add_child(visual)
			if visual is Node3D:
				visual.position.y = 0.0
				visual.scale = Vector3.ONE * (cell_size / 3.0)
				_align_visual_base_to_ground(visual, 0.0)
		_add_hiding_solid(zone)


func spawn_collectibles() -> void:
	if items_root == null:
		_resolve_level_nodes()
	_clear_children(items_root)
	var count := maxi(0, collectible_count)
	var cells := _take_random_cells(count)
	for index in cells.size():
		var item := InteractableItem.new()
		item.name = "%s_%02d" % [ITEM_NAMES[index % ITEM_NAMES.size()], index + 1]
		item.item_name = ITEM_NAMES[index % ITEM_NAMES.size()]
		item.item_type = ITEM_TYPES[index % ITEM_TYPES.size()]
		item.position = _cell_to_world(cells[index]) + Vector3.UP * 0.55
		item.rotation.y = _rng.randf_range(0.0, TAU)
		items_root.add_child(item)
		var item_scene := _collectible_scene_for_type(item.item_type, index)
		if item_scene != null:
			var visual := item_scene.instantiate()
			item.add_child(visual)
			if visual is Node3D:
				visual.scale = Vector3.ONE * 0.65
				_align_visual_base_to_ground(visual, 0.0)
		else:
			_add_fallback_collectible_visual(item, item.item_type)
	if player != null and player.get("total_items_needed") != null:
		player.set("total_items_needed", count)


func _collectible_scene_for_type(item_type: InteractableItem.ItemType, index: int) -> PackedScene:
	var keywords: Array[String] = []
	match item_type:
		InteractableItem.ItemType.CAULDRON:
			keywords = ["cauldron"]
		InteractableItem.ItemType.POTION:
			keywords = ["potion", "phial", "vial", "elixir"]
		InteractableItem.ItemType.PUMPKIN:
			keywords = ["pumpkin"]
		InteractableItem.ItemType.SPELLBOOK:
			keywords = ["spellbook", "spell_book", "spell-book", "book", "grimoire"]
	for scene in collectible_scenes:
		var asset_name := scene.resource_path.get_file().get_basename().to_lower()
		for keyword in keywords:
			if asset_name.contains(keyword):
				return scene
	# For manually assigned generic scenes, preserve the Inspector's type order.
	if collectible_scenes.size() >= ITEM_TYPES.size() and index < collectible_scenes.size():
		return collectible_scenes[index]
	return null


func generate_patrol_points() -> void:
	if patrol_points_root == null:
		patrol_points_root = _ensure_container(self, "PatrolPoints")
	_clear_children(patrol_points_root)
	var candidates: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(grid_size.x - 1, 0),
		Vector2i(grid_size.x - 1, grid_size.y - 1),
		Vector2i(0, grid_size.y - 1),
	]
	var markers: Array[Node3D] = []
	for index in candidates.size():
		var cell := _nearest_walkable_cell(candidates[index])
		var marker := Marker3D.new()
		marker.name = "PatrolPoint_%02d" % (index + 1)
		marker.position = _cell_to_world(cell)
		patrol_points_root.add_child(marker)
		markers.append(marker)
	_patrol_markers = markers
	if enemy is EnemyAI:
		enemy.call("configure_patrol_route", markers)


func bake_navigation() -> void:
	if navigation_region == null or navigation_region.navigation_mesh == null:
		push_warning("No hay NavigationRegion3D o NavigationMesh para hornear.")
		return
	if not navigation_region.is_inside_tree():
		push_warning("NavigationRegion3D debe estar dentro del árbol antes del horneado.")
		return
	navigation_region.bake_navigation_mesh(false)
	_activate_enemy_navigation()


func _activate_enemy_navigation() -> void:
	if not (enemy is EnemyAI) or _patrol_markers.is_empty():
		return
	var agent := enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent == null:
		return
	enemy.call("start_patrol")


func _ensure_player_and_enemy() -> void:
	player = get_node_or_null("Player") as CharacterBody3D
	if player == null:
		player = PlayerController.new()
		player.name = "Player"
		add_child(player)
		var camera := Camera3D.new()
		camera.name = "Camera3D"
		camera.position.y = 0.55
		player.add_child(camera)
		var ray := RayCast3D.new()
		ray.name = "RayCast3D"
		ray.target_position = Vector3(0.0, 0.0, -3.0)
		ray.collide_with_areas = true
		camera.add_child(ray)
		player.set("camera", camera)
		player.set("interaction_ray", ray)
	var attached_player_collision := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if attached_player_collision == null:
		attached_player_collision = CollisionShape3D.new()
		attached_player_collision.name = "CollisionShape3D"
		player.add_child(attached_player_collision)
	var player_capsule := CapsuleShape3D.new()
	player_capsule.radius = 0.3
	player_capsule.height = 1.7
	attached_player_collision.shape = player_capsule
	attached_player_collision.position.y = 0.0
	player.collision_mask = player.collision_mask | 1
	if player.has_method("add_to_group"):
		player.add_to_group("player")

	enemy = get_node_or_null("Enemy") as CharacterBody3D
	if enemy == null:
		enemy = EnemyAI.new()
		enemy.name = "Enemy"
		add_child(enemy)
	var attached_enemy_collision := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if attached_enemy_collision == null:
		attached_enemy_collision = CollisionShape3D.new()
		attached_enemy_collision.name = "CollisionShape3D"
		attached_enemy_collision.shape = CapsuleShape3D.new()
		enemy.add_child(attached_enemy_collision)
	attached_enemy_collision.position.y = 0.0
	enemy.collision_mask = enemy.collision_mask | 1
	var navigation_agent := enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent == null:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.name = "NavigationAgent3D"
		enemy.add_child(navigation_agent)
	if enemy is EnemyAI:
		enemy.set("player", player)
		enemy.set("navigation_agent", navigation_agent)


func _place_player_and_enemy() -> void:
	var player_cell := Vector2i(0, 0)
	var enemy_cell := Vector2i(grid_size.x - 1, grid_size.y - 1)
	_free_cells.erase(player_cell)
	_free_cells.erase(enemy_cell)
	player.position = Vector3(0.0, 1.0, 0.0)
	enemy.position = Vector3(float(enemy_cell.x) * cell_size, 0.0, float(enemy_cell.y) * cell_size)
	enemy.velocity = Vector3.ZERO
	enemy.visible = true
	_configure_enemy_visual_and_collision()
	# Keep the CharacterBody origin on the map floor; visual offsets belong to EnemyVisual.
	enemy.position.y = 0.0
	var map_center := to_global(Vector3(
		float(grid_size.x - 1) * cell_size * 0.5,
		0.0,
		float(grid_size.y - 1) * cell_size * 0.5
	))
	if player.has_method("orient_toward"):
		player.call("orient_toward", map_center)
	else:
		player.look_at(Vector3(map_center.x, player.global_position.y, map_center.z), Vector3.UP)
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.position.y = 0.55
		camera.rotation = Vector3.ZERO


func _add_hiding_solid(zone: HidingZone) -> void:
	var solid := StaticBody3D.new()
	solid.name = "HidingStructureCollision"
	solid.collision_layer = 1
	solid.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(cell_size * 0.65, 1.8, cell_size * 0.65)
	collision.shape = shape
	collision.position.y = 0.9
	solid.add_child(collision)
	zone.add_child(solid)


func _configure_enemy_visual_and_collision() -> void:
	for child in enemy.get_children():
		if child.name in ["EnemyPlaceholderMesh", "EnemyFallbackMesh"]:
			enemy.remove_child(child)
			child.free()
	var visual_root := enemy.get_node_or_null("EnemyVisual") as Node3D
	if visual_root == null:
		visual_root = Node3D.new()
		visual_root.name = "EnemyVisual"
		enemy.add_child(visual_root)
	_clear_children(visual_root)
	var skeleton_scene := _find_enemy_model_scene()
	if skeleton_scene != null:
		var skeleton := skeleton_scene.instantiate()
		skeleton.name = "SkeletonBody"
		visual_root.add_child(skeleton)
		if skeleton is Node3D:
			skeleton.scale = Vector3.ONE * 0.78
	else:
		_build_asset_skeleton(visual_root)
	var body_bounds := _get_combined_visual_aabb(visual_root)
	if body_bounds.size == Vector3.ZERO:
		body_bounds = AABB(Vector3(-0.4, 0.0, -0.3), Vector3(0.8, 1.35, 0.6))
	var pumpkin_scene := _find_pumpkin_head_scene()
	if pumpkin_scene != null:
		var pumpkin_head := pumpkin_scene.instantiate()
		pumpkin_head.name = "PumpkinHead"
		visual_root.add_child(pumpkin_head)
		if pumpkin_head is Node3D:
			pumpkin_head.scale = Vector3.ONE * 0.62
			var head_bounds := _get_combined_visual_aabb(pumpkin_head)
			var scaled_head_min: Vector3 = head_bounds.position * pumpkin_head.scale
			var scaled_head_size: Vector3 = head_bounds.size * pumpkin_head.scale
			var body_center: Vector3 = body_bounds.position + body_bounds.size * 0.5
			var head_center: Vector3 = scaled_head_min + scaled_head_size * 0.5
			var head_bottom_y := body_bounds.position.y + body_bounds.size.y - 0.1
			pumpkin_head.position = Vector3(
				body_center.x - head_center.x,
				head_bottom_y - scaled_head_min.y,
				body_center.z - head_center.z
			)
		_add_enemy_pumpkin_light(pumpkin_head)
	else:
		push_warning("No se encontró una calabaza jack-o'-lantern para la cabeza del enemigo.")
	_normalize_enemy_visual_origin(visual_root)
	if enemy.has_method("configure_appearance"):
		enemy.call("configure_appearance", visual_root)
	else:
		_fit_enemy_collision_to_visual()
	var agent := enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		agent.avoidance_enabled = true
		agent.radius = navigation_agent_radius
		agent.height = navigation_agent_height
		agent.path_height_offset = 0.0


func _normalize_enemy_visual_origin(visual_root: Node3D) -> void:
	var bounds := _get_combined_visual_aabb(visual_root)
	if bounds.size == Vector3.ZERO:
		visual_root.position.y = 0.0
		return
	# Move imported model roots so their lowest visible point is at the enemy origin,
	# while keeping the EnemyVisual Node3D itself at y=0.
	var base_offset := -bounds.position.y
	for child in visual_root.get_children():
		if child is Node3D:
			child.position.y += base_offset
	visual_root.position.y = 0.0


func _find_enemy_model_scene() -> PackedScene:
	for scene in _halloween_scenes:
		var asset_name := scene.resource_path.get_file().get_basename().to_lower()
		for keyword in ENEMY_MODEL_KEYWORDS:
			if asset_name.contains(keyword):
				return scene
	return null


func _find_pumpkin_head_scene() -> PackedScene:
	for path in ENEMY_PUMPKIN_HEAD_ASSETS:
		var scene := load(path) as PackedScene
		if scene != null:
			return scene
	for scene in _halloween_scenes:
		var asset_name := scene.resource_path.get_file().get_basename().to_lower()
		if asset_name.contains("pumpkin") and (asset_name.contains("jackolantern") or asset_name.contains("jack_o_lantern")):
			return scene
	return null


func _build_asset_skeleton(parent: Node3D) -> void:
	# This KayKit folder has ribcage/bone props rather than a complete skeleton mesh.
	var body := Node3D.new()
	body.name = "SkeletonBody"
	parent.add_child(body)
	_add_enemy_asset_part(body, ENEMY_BODY_PART_ASSETS[0], Vector3(0.0, 0.9, 0.0), Vector3.ONE * 0.82)
	_add_enemy_asset_part(body, ENEMY_BODY_PART_ASSETS[1], Vector3(-0.38, 0.95, 0.0), Vector3.ONE * 0.7, -0.62)
	_add_enemy_asset_part(body, ENEMY_BODY_PART_ASSETS[2], Vector3(0.38, 0.95, 0.0), Vector3.ONE * 0.7, 0.62)
	_add_enemy_asset_part(body, ENEMY_BODY_PART_ASSETS[3], Vector3(-0.16, 0.34, 0.0), Vector3.ONE * 0.58, -0.08)
	_add_enemy_asset_part(body, ENEMY_BODY_PART_ASSETS[3], Vector3(0.16, 0.34, 0.0), Vector3.ONE * 0.58, 0.08)


func _add_enemy_pumpkin_light(pumpkin_head: Node) -> void:
	var light := OmniLight3D.new()
	light.name = "PumpkinGlow"
	light.light_color = Color(1.0, 0.19, 0.035)
	light.light_energy = 0.75
	light.omni_range = 3.5
	light.shadow_enabled = false
	light.position = Vector3(0.0, 0.0, -0.08)
	pumpkin_head.add_child(light)


func _add_enemy_asset_part(parent: Node3D, asset_path: String, local_position: Vector3, part_scale: Vector3, rotation_z: float = 0.0) -> void:
	var packed := load(asset_path) as PackedScene
	if packed == null:
		return
	var part := packed.instantiate()
	part.name = asset_path.get_file().get_basename()
	parent.add_child(part)
	if part is Node3D:
		part.position = local_position
		part.scale = part_scale
		part.rotation.z = rotation_z


func _fit_enemy_collision_to_visual() -> void:
	var collision := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		enemy.add_child(collision)
	var bounds := _get_combined_visual_aabb(enemy)
	var width := maxf(bounds.size.x, bounds.size.z)
	var radius := clampf(width * 0.3, 0.28, 0.55)
	var height := maxf(bounds.size.y, radius * 2.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	collision.shape = capsule
	collision.position = bounds.position + Vector3(bounds.size.x * 0.5, bounds.size.y * 0.5, bounds.size.z * 0.5)


func _get_combined_visual_aabb(root: Node3D) -> AABB:
	var combined := AABB()
	var has_bounds := false
	var visual_nodes: Array[Node] = []
	if root is VisualInstance3D:
		visual_nodes.append(root)
	visual_nodes.append_array(root.find_children("*", "VisualInstance3D", true, false))
	var root_inverse := root.global_transform.affine_inverse()
	for node in visual_nodes:
		var visual := node as VisualInstance3D
		if visual == null:
			continue
		var relative_transform := root_inverse * visual.global_transform
		var visual_bounds := relative_transform * visual.get_aabb()
		if not has_bounds:
			combined = visual_bounds
			has_bounds = true
		else:
			combined = combined.merge(visual_bounds)
	return combined if has_bounds else AABB()


func _align_visual_base_to_ground(root: Node3D, ground_y: float = 0.0) -> void:
	var bounds := _get_combined_visual_aabb(root)
	if bounds.size == Vector3.ZERO:
		return
	root.position.y += ground_y - root.global_position.y - bounds.position.y


func _spawn_passage_decorations() -> void:
	if _decoration_scenes.is_empty() or _free_cells.is_empty():
		return
	var candidates := _free_cells.duplicate()
	var scene_bag: Array[PackedScene] = _decoration_scenes.duplicate()
	scene_bag.shuffle()
	var target_count := mini(candidates.size(), roundi(float(candidates.size()) * decoration_density))
	for index in target_count:
		if scene_bag.is_empty():
			scene_bag = _decoration_scenes.duplicate()
			scene_bag.shuffle()
		var cell_index := _rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates.pop_at(cell_index)
		var scene: PackedScene = scene_bag.pop_back()
		var asset_name := scene.resource_path.get_file().get_basename().to_lower()
		var prop_body := StaticBody3D.new()
		prop_body.name = "PassageProp_%02d" % (index + 1)
		prop_body.collision_layer = 1
		prop_body.collision_mask = 1
		var jitter := Vector3(_rng.randf_range(-0.25, 0.25) * cell_size, 0.0, _rng.randf_range(-0.25, 0.25) * cell_size)
		prop_body.position = _cell_to_world(cell) + jitter
		prop_body.rotation.y = _rng.randf_range(0.0, TAU)
		environment_root.add_child(prop_body)
		var visual := scene.instantiate()
		prop_body.add_child(visual)
		_strip_embedded_colliders(visual)
		if visual is Node3D:
			visual.scale = Vector3.ONE * _decoration_scale_for(asset_name)
			_align_visual_base_to_ground(visual, 0.0)
		if _is_passable_arch_asset(asset_name):
			_add_arch_pillar_collisions(prop_body)
		else:
			_add_visual_bounds_collision(prop_body, "DecorationCollision", asset_name)


func _decoration_scale_for(asset_name: String) -> float:
	if asset_name.contains("candle") or asset_name.contains("skull_candle") or asset_name.contains("plaque"):
		return 0.38
	if asset_name.contains("bone_") or asset_name.contains("skull") or asset_name.contains("pumpkin"):
		return 0.48
	if asset_name.contains("tree_") or asset_name.contains("arch") or asset_name.contains("gate"):
		return 0.58
	return 0.52


func _add_visual_bounds_collision(parent: StaticBody3D, collision_name: String, asset_name: String = "", minimum_height: float = 0.0) -> void:
	var bounds := _get_combined_visual_aabb(parent)
	if bounds.size.x < 0.12 or bounds.size.y < 0.12 or bounds.size.z < 0.12:
		return
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	if asset_name.contains("tree_"):
		var trunk := CylinderShape3D.new()
		trunk.radius = clampf(minf(bounds.size.x, bounds.size.z) * 0.12, 0.18, 0.32)
		trunk.height = maxf(trunk.radius * 2.0, minf(bounds.size.y, 1.8))
		collision.shape = trunk
		collision.position = Vector3(bounds.position.x + bounds.size.x * 0.5, bounds.position.y + trunk.height * 0.5, bounds.position.z + bounds.size.z * 0.5)
	else:
		var shape := BoxShape3D.new()
		shape.size = Vector3(bounds.size.x, maxf(bounds.size.y, minimum_height), bounds.size.z)
		collision.shape = shape
		collision.position = bounds.position + bounds.size * 0.5
		if minimum_height > bounds.size.y:
			collision.position.y = minimum_height * 0.5
	parent.add_child(collision)


func _strip_embedded_colliders(root: Node) -> void:
	# Generated static bodies receive a controlled collider in the builder. Removing
	# import-side simplified boxes prevents arches from sealing their center opening.
	var shapes := root.find_children("*", "CollisionShape3D", true, false)
	for node in shapes:
		var shape_node := node as CollisionShape3D
		if shape_node != null and shape_node.get_parent() != null:
			shape_node.get_parent().remove_child(shape_node)
			shape_node.free()
	var polygons := root.find_children("*", "CollisionPolygon3D", true, false)
	for node in polygons:
		var polygon_node := node as CollisionPolygon3D
		if polygon_node != null and polygon_node.get_parent() != null:
			polygon_node.get_parent().remove_child(polygon_node)
			polygon_node.free()


func _add_fallback_collectible_visual(item: Node3D, item_type: InteractableItem.ItemType) -> void:
	if item_type == InteractableItem.ItemType.PUMPKIN:
		var pumpkin_scene := load(PUMPKIN_ASSET_PATH) as PackedScene
		if pumpkin_scene != null:
			var pumpkin := pumpkin_scene.instantiate()
			item.add_child(pumpkin)
			if pumpkin is Node3D:
				pumpkin.scale = Vector3.ONE * 0.65
				_align_visual_base_to_ground(pumpkin, 0.0)
			return
	var visual_root := Node3D.new()
	visual_root.name = "PlaceholderVisual"
	item.add_child(visual_root)
	var mesh_instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	match item_type:
		InteractableItem.ItemType.CAULDRON:
			var cauldron := CylinderMesh.new()
			cauldron.top_radius = 0.38
			cauldron.bottom_radius = 0.32
			cauldron.height = 0.48
			mesh_instance.mesh = cauldron
			material.albedo_color = Color(0.12, 0.1, 0.13)
		InteractableItem.ItemType.POTION:
			var potion := SphereMesh.new()
			potion.radius = 0.25
			potion.height = 0.5
			mesh_instance.mesh = potion
			material.albedo_color = Color(0.75, 0.12, 0.18)
		InteractableItem.ItemType.SPELLBOOK:
			var book := BoxMesh.new()
			book.size = Vector3(0.45, 0.12, 0.34)
			mesh_instance.mesh = book
			material.albedo_color = Color(0.24, 0.1, 0.32)
	mesh_instance.position.y = 0.15
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	_align_visual_base_to_ground(visual_root, 0.0)


func _default_obstacle_scenes() -> Array[PackedScene]:
	var defaults: Array[PackedScene] = []
	for path in OBSTACLE_ASSET_PATHS:
		var scene := load(path) as PackedScene
		if scene != null:
			defaults.append(scene)
	return defaults


func _default_hiding_scenes() -> Array[PackedScene]:
	var defaults: Array[PackedScene] = []
	for path in HIDING_ASSET_PATHS:
		var scene := load(path) as PackedScene
		if scene != null:
			defaults.append(scene)
	return defaults


func _pick_scene(configured: Array[PackedScene], fallbacks: Array[PackedScene]) -> PackedScene:
	var source := configured if not configured.is_empty() else fallbacks
	var choices: Array[PackedScene] = []
	for scene in source:
		var asset_name := scene.resource_path.get_file().get_basename().to_lower()
		if not _is_hanging_lantern_asset(asset_name):
			choices.append(scene)
	if choices.is_empty():
		return null
	return choices[_rng.randi_range(0, choices.size() - 1)]


func _take_random_cells(requested_count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pool := _free_cells.duplicate()
	while not pool.is_empty() and result.size() < requested_count:
		var index := _rng.randi_range(0, pool.size() - 1)
		var cell: Vector2i = pool.pop_at(index)
		result.append(cell)
		_free_cells.erase(cell)
	return result


func _nearest_walkable_cell(from_cell: Vector2i) -> Vector2i:
	if not _blocked_cells.has(from_cell):
		return from_cell
	if _free_cells.is_empty():
		return Vector2i.ZERO
	var nearest: Vector2i = _free_cells[0]
	for cell in _free_cells:
		if from_cell.distance_squared_to(cell) < from_cell.distance_squared_to(nearest):
			nearest = cell
	return nearest


func _is_protected_corridor(cell: Vector2i, center_x: int, center_z: int) -> bool:
	return cell.x == 0 or cell.y == 0 \
		or cell.x == grid_size.x - 1 or cell.y == grid_size.y - 1 \
		or cell.x == center_x or cell.y == center_z


func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * cell_size, 0.0, float(cell.y) * cell_size)


func _ensure_container(parent: Node, child_name: String) -> Node3D:
	var container := parent.get_node_or_null(NodePath(child_name)) as Node3D
	if container == null:
		container = Node3D.new()
		container.name = child_name
		parent.add_child(container)
	return container


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()

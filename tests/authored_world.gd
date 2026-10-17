extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var logger := root.get_node_or_null("GameplayLog")
	if logger != null:
		logger.set_process(false)
		logger.set_meta("test_run", true)
	for index in range(1, 5):
		var packed := load("res://scenes/Level_%02d.tscn" % index) as PackedScene
		var edited: Node3D = packed.instantiate()
		edited.bake_navigation_after_build = false
		edited.process_mode = Node.PROCESS_MODE_DISABLED
		var altar: Node3D = edited.get_node("RitualAltars").get_child(0)
		altar.position += Vector3(0.5, 0, 0.5)
		var altar_expected: Vector3 = altar.position
		var initial_player: Node3D = edited.get_node("Player")
		initial_player.position += Vector3(0.2, 0, 0.2)
		var player_expected: Vector3 = initial_player.position
		var first_enemy: Node3D = edited.get_node("Enemy1")
		first_enemy.position += Vector3(0.25, 0, 0.25)
		var enemy_expected: Vector3 = first_enemy.position
		var enemy_shape: CollisionShape3D = first_enemy.get_node("CollisionShape3D")
		enemy_shape.position.y = 1.13
		var marker: Node3D = edited.get_node("PatrolPoints").get_child(0)
		marker.position += Vector3(0.3, 0, 0.3)
		var marker_expected: Vector3 = marker.position
		var sunlight: DirectionalLight3D = edited.get_node("DirectionalLight3D")
		sunlight.light_energy = 0.37
		var environment: Node3D = edited.get_node("NavigationRegion3D/Environment")
		var before_children := environment.get_child_count()
		var prop: Node3D = environment.get_child(environment.get_child_count() - 1)
		var prop_path := edited.get_path_to(prop)
		prop.position += Vector3(0.3, 0, 0.3)
		var prop_expected := prop.position
		var saved := PackedScene.new()
		check(saved.pack(edited) == OK, "Level %d editor pack" % index)
		var temporary := "/private/tmp/resonance-authoring-test-%d.tscn" % index
		check(ResourceSaver.save(saved, temporary) == OK, "Level %d editor save" % index)
		edited.free()
		var reloaded := ResourceLoader.load(temporary, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var level: Node3D = reloaded.instantiate()
		root.add_child(level)
		current_scene = level
		check(level.has_meta("authored_layout") and not level.auto_build_on_ready, "Level %d uses saved map" % index)
		check(level.get_node("NavigationRegion3D/Environment").get_child_count() == before_children, "Level %d map not regenerated" % index)
		check(level.get_node(prop_path).position.is_equal_approx(prop_expected), "Level %d moved scenery persists" % index)
		check(level.player.position.is_equal_approx(player_expected), "Level %d player spawn edit persists" % index)
		check(level.enemies.size() == [2, 3, 3, 4][index - 1], "Level %d original enemy count" % index)
		check(level.enemies[0].position.is_equal_approx(enemy_expected), "Level %d enemy spawn edit persists" % index)
		check(is_equal_approx(level.enemies[0].get_node("CollisionShape3D").position.y, 1.13), "Level %d enemy collision edit persists" % index)
		check(level.enemies[0].patrol_points[0].position.is_equal_approx(marker_expected), "Level %d edited patrol marker used" % index)
		check(level.ritual_shrines.size() == [2, 4, 4, 4][index - 1], "Level %d original altar count" % index)
		check(level.ritual_shrines[0].position.is_equal_approx(altar_expected), "Level %d moved altar used" % index)
		check(is_equal_approx(level.get_node("DirectionalLight3D").light_energy, 0.37), "Level %d authored light preserved" % index)
		check(level.active_pumpkins.size() == [0, 0, 7, 4][index - 1], "Level %d original pumpkin count" % index)
		check(not get_nodes_in_group("hide_objects").is_empty(), "Level %d cover groups remain usable" % index)
		check(level.absolute_ritual_relics.size() == (2 if index == 4 else 0), "Level %d original relic count" % index)
		check(level.ritual_shrines[0].activate(), "Level %d altar activates" % index)
		check(not level.ritual_shrines[0].activate(), "Level %d altar cannot activate twice" % index)
		level._open_exit_gate()
		check(level._exit_gate_is_open and level.exit_gate_barrier.collision_layer == 0, "Level %d gate opens" % index)
		if index >= 2:
			check(level.active_skulls.size() == 3, "Level %d original skull count" % index)
			for pickup in level.active_skulls.duplicate():
				pickup.position += Vector3(0.4, 0, 0)
				level.player.global_position = pickup.global_position + Vector3.UP
				level.player.current_health = level.player.max_health - 1
				check(level.try_collect_nearby_health_skull(level.player), "Level %d moved health pickup works" % index)
			check(level._health_skull_respawns_remaining == 3, "Level %d original health respawn cycle" % index)
			level._on_health_skull_respawn_timeout()
			check(level.active_skulls.size() == 1, "Level %d health respawns using editable markers" % index)
		if index >= 3:
			var pumpkin: Node3D = level.active_pumpkins[0]
			pumpkin.position += Vector3(0.4, 0, 0)
			level.player.global_position = pumpkin.global_position + Vector3.UP
			check(level.try_collect_nearby_pumpkin(level.player), "Level %d moved pumpkin works" % index)
			check(level.player.pumpkins_collected == 1, "Level %d pumpkin mission increments" % index)
		if index == 4:
			level.player.pumpkins_collected = 4
			var relic: Node3D = level.absolute_ritual_relics[0]
			relic.position += Vector3(0.4, 0, 0)
			level.player.global_position = relic.global_position + Vector3.UP
			check(level.try_interact_absolute_ritual_relic(level.player), "Moved relic can be carried")
			level.player.global_position = level.absolute_ritual_delivery_position + Vector3.UP
			check(level.try_interact_absolute_ritual_relic(level.player), "Carried relic can be delivered")
			check(level.absolute_ritual_relics_delivered == 1, "Delivery mission increments")
		await create_timer(0.15).timeout
		stop_audio(level)
		await create_timer(0.15).timeout
		level.queue_free()
		paused = false
		await process_frame
		DirAccess.remove_absolute(temporary)
	await create_timer(0.15).timeout
	print("AUTHORED_WORLD_CHECKS ", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
		node.stop()
	for child in node.get_children():
		stop_audio(child)

extends GutTest

const MainScene: PackedScene = preload("res://scenes/main.tscn")


func test_forage_nodes_cover_z01_to_z03_with_rising_mushroom_risk() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var valley := main.get_node("World") as ValleyMap
	var forage := main.get_node("ForageNodes")
	var counts := {"Z01": {}, "Z02": {}, "Z03": {}}
	for node: Node in forage.get_children():
		var world_node := node as Node2D
		var zone := valley.zone_at_world(world_node.global_position)
		assert_true(zone in counts, "%s must sit in the open slice" % node.name)
		var item_id: StringName = node.item_id if node is WorldItem else node.reward_id
		counts[zone][item_id] = int(counts[zone].get(item_id, 0)) + 1
	assert_gt(int(counts.Z01.get(&"berry", 0)), int(counts.Z01.get(&"toxic_mushroom", 0)))
	assert_gt(int(counts.Z02.get(&"mushroom", 0)), 0)
	assert_gt(int(counts.Z03.get(&"toxic_mushroom", 0)), 0)


func test_scene_owned_forage_nodes_receive_difficulty_respawn_registration() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	for node: Node in main.get_node("ForageNodes").get_children():
		assert_not_null(node.owner, "%s is scene-owned" % node.name)
		if node is WorldItem:
			assert_gt(node.resource_respawn_seconds, 0.0, "%s respawns" % node.name)
		else:
			assert_gt(node.respawn_seconds, 0.0, "%s respawns" % node.name)

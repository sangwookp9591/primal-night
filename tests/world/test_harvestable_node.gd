extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const HarvestScene: PackedScene = preload("res://scenes/items/harvestable_node.tscn")


func _pair(kind: String = "tree") -> Dictionary:
	var root: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var player: Player = PlayerScene.instantiate()
	root.add_child(player)
	var node: HarvestableNode = HarvestScene.instantiate()
	node.position = Vector2(24.0, 0.0)
	node.harvest_kind = kind
	node.reward_id = &"berry" if kind == "berry_bush" else &"wood"
	node.reward_count = 1 if kind == "berry_bush" else 2
	node.hold_seconds = 0.4 if kind == "berry_bush" else 2.75
	node.vegetation_index = 4 if kind == "berry_bush" else 0
	root.add_child(node)
	return {player = player, node = node}


func test_tree_hold_grants_wood_and_depletes() -> void:
	var pair := _pair()
	var player: Player = pair.player
	var node: HarvestableNode = pair.node
	assert_eq(node.get_prompt(), "나무 베기")
	assert_eq(node.get_hold_seconds(), 2.75)
	assert_true(node.apply_harvest(player))
	assert_eq(player.inventory.count_of(&"wood"), 2)
	assert_false(node.available)
	assert_false(node.monitorable)


func test_depleted_tree_respawns_on_host_timer() -> void:
	var pair := _pair()
	var node: HarvestableNode = pair.node
	node.respawn_seconds = 0.05
	assert_true(node.apply_harvest(pair.player))
	assert_true(await wait_until(func() -> bool: return node.available, 1.0))
	assert_true(node.monitorable)


func test_berry_bush_pick_changes_to_empty_then_restores_berries() -> void:
	var pair := _pair("berry_bush")
	var player: Player = pair.player
	var node: HarvestableNode = pair.node
	node.respawn_seconds = 0.05
	assert_true(node.get_node("BerryOverlay").visible)
	assert_true(node.apply_harvest(player))
	assert_eq(player.inventory.count_of(&"berry"), 1)
	assert_false(node.get_node("BerryOverlay").visible)
	assert_true(await wait_until(func() -> bool: return node.available, 1.0))
	assert_true(node.get_node("BerryOverlay").visible)


func test_harvest_rhythm_emits_noise() -> void:
	var pair := _pair()
	var player: Player = pair.player
	var node: HarvestableNode = pair.node
	watch_signals(get_node("/root/EventBus"))
	node.on_hold_started(player)
	await wait_process_frames(2)
	node.on_hold_ended(player)
	assert_gt(get_signal_emit_count(get_node("/root/EventBus"), "noise_emitted"), 0)

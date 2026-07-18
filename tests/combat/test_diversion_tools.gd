extends GutTest

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const ThrowNoise: NoiseProfile = preload("res://data/senses/noise_throw.tres")
const FluteNoise: NoiseProfile = preload("res://data/senses/noise_lure.tres")

var _event_bus: Node


func before_each() -> void:
	_event_bus = get_node("/root/EventBus")


func test_catalog_and_recipes_preserve_material_competition_contract() -> void:
	var data := get_node("/root/GameData")
	var flute := data.get_item(&"bone_flute") as ItemData
	var pouch := data.get_item(&"bait_pouch") as ItemData
	assert_not_null(flute)
	assert_not_null(pouch)
	assert_true(pouch.is_smell_source())
	assert_eq(data.get_recipe(&"craft_bone_flute").ingredients,
		{&"bone": 1, &"sinew": 1})
	assert_eq(data.get_recipe(&"craft_bait_pouch").ingredients,
		{&"hide": 1, &"raw_meat": 1})


func test_stone_aim_throw_consumes_one_and_emits_impact_noise() -> void:
	var main := add_child_autofree(MainScene.instantiate()) as Node2D
	var player := main.get_node("Player") as Player
	var combat := main.get_node("NetCombat") as NetCombat
	assert_eq(player.inventory.add_item(&"stone", 2), 2)
	watch_signals(_event_bus)

	assert_true(combat.request_throw_aim(player, true, Vector2.RIGHT))
	assert_true(player.throw_aiming)
	assert_true(combat.request_throw_fire(player, Vector2.RIGHT))
	assert_false(player.throw_aiming)
	assert_eq(player.inventory.count_of(&"stone"), 1)
	await wait_seconds(NetCombat.THROW_RANGE / NetCombat.THROW_SPEED + 0.1)

	assert_signal_emitted(_event_bus, "noise_emitted")
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_almost_eq((params[0] as Vector2).distance_to(
		player.global_position + Vector2.RIGHT * NetCombat.THROW_RANGE), 0.0, 2.0)
	assert_eq(params[1], ThrowNoise.radius)


func test_bone_flute_is_reusable_and_noise_origin_is_the_player() -> void:
	var main := add_child_autofree(MainScene.instantiate()) as Node2D
	var player := main.get_node("Player") as Player
	var combat := main.get_node("NetCombat") as NetCombat
	player.global_position = Vector2(210.0, 180.0)
	assert_eq(player.inventory.add_item(&"bone_flute", 1), 1)
	watch_signals(_event_bus)

	assert_true(combat.request_bone_flute(player))

	assert_eq(player.inventory.count_of(&"bone_flute"), 1)
	assert_signal_emitted(_event_bus, "noise_emitted")
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[0], player.global_position)
	assert_eq(params[1], FluteNoise.radius)


func test_bait_pouch_lands_as_persistent_world_smell_source() -> void:
	var main := add_child_autofree(MainScene.instantiate()) as Node2D
	var player := main.get_node("Player") as Player
	var combat := main.get_node("NetCombat") as NetCombat
	assert_eq(player.inventory.add_item(&"bait_pouch", 1), 1)

	assert_true(combat.request_throw_aim(player, true, Vector2.RIGHT))
	assert_true(combat.request_throw_fire(player, Vector2.RIGHT))
	await wait_seconds(NetCombat.THROW_RANGE / NetCombat.THROW_SPEED + 0.1)

	assert_eq(player.inventory.count_of(&"bait_pouch"), 0)
	var landed := main.get_node_or_null("LandedBaitPouch1") as WorldItem
	assert_not_null(landed)
	assert_eq(landed.item_id, &"bait_pouch")
	assert_almost_eq(landed.global_position.distance_to(
		player.global_position + Vector2.RIGHT * NetCombat.THROW_RANGE), 0.0, 2.0)
	var smell_source: SmellSource = null
	for child: Node in landed.get_children():
		if child is SmellSource:
			smell_source = child
			break
	assert_not_null(smell_source)


func test_host_rejects_forged_throw_owner_without_consuming_inventory() -> void:
	var main := add_child_autofree(MainScene.instantiate()) as Node2D
	var player := main.get_node("Player") as Player
	var combat := main.get_node("NetCombat") as NetCombat
	assert_eq(player.inventory.add_item(&"stone", 1), 1)

	combat.submit_throw_fire_intent("forged-player", Vector2.RIGHT)

	assert_eq(player.inventory.count_of(&"stone"), 1)

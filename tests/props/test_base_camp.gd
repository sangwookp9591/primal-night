extends GutTest

var main: Node
var player: Player
var cache: StorageCache
var rack: DryingRack
var bedding: Bedding
var net: NetBaseCamp

func before_each() -> void:
	main = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	player = main.get_node("Player") as Player
	cache = main.get_node("StorageCache") as StorageCache
	rack = main.get_node("DryingRack") as DryingRack
	bedding = main.get_node("Bedding") as Bedding
	net = main.get_node("NetBaseCamp") as NetBaseCamp
	player.global_position = cache.global_position

func test_storage_transfer_is_atomic_and_duplicate_request_preserves_total() -> void:
	assert_eq(player.inventory.add_item(&"wood", 1), 1)
	assert_true(net._host_storage_transfer(cache, player, &"wood", true))
	assert_false(net._host_storage_transfer(cache, player, &"wood", true),
		"동시에 도착한 두 번째 요청은 원본이 없으므로 거부한다")
	assert_eq(player.inventory.count_of(&"wood") + cache.inventory.count_of(&"wood"), 1)
	assert_true(net._host_storage_transfer(cache, player, &"wood", false))
	assert_eq(player.inventory.count_of(&"wood"), 1)
	assert_eq(cache.inventory.count_of(&"wood"), 0)

func test_storage_destination_failure_rolls_back_both_inventories() -> void:
	assert_eq(player.inventory.add_item(&"wood", 1), 1)
	cache.inventory.max_weight = 0.0
	assert_false(net._host_storage_transfer(cache, player, &"wood", true))
	assert_eq(player.inventory.count_of(&"wood"), 1)
	assert_eq(cache.inventory.count_of(&"wood"), 0)

func test_drying_converts_on_host_and_reduces_smell() -> void:
	player.global_position = rack.global_position
	assert_eq(player.inventory.add_item(&"raw_meat", 1), 1)
	assert_true(net._host_drying(rack, player))
	assert_eq(rack.item_id, &"raw_meat")
	assert_eq(rack.current_smell_strength(), rack.raw_smell_strength)
	rack._physics_process(rack.drying_seconds)
	assert_eq(rack.item_id, &"dried_meat")
	assert_eq(rack.current_smell_strength(), rack.dried_smell_strength)
	assert_lt(rack.dried_smell_strength, rack.raw_smell_strength)

func test_bedding_accelerates_fatigue_recovery_without_clock_change() -> void:
	player.stats.fatigue = 80.0
	player.stats.reset_motion_baseline()
	var normal_before := player.stats.fatigue
	player.stats.simulate(1.0)
	var normal_recovery := normal_before - player.stats.fatigue
	player.stats.fatigue = 80.0
	player.global_position = bedding.global_position
	player.stats.reset_motion_baseline()
	net._host_bedding(bedding, player, true, bedding.fatigue_recovery_multiplier)
	player.stats.simulate(1.0)
	var bedding_recovery := 80.0 - player.stats.fatigue
	assert_gt(bedding_recovery, normal_recovery)

func test_base_recipes_use_only_shared_materials() -> void:
	var allowed := [&"wood", &"fiber", &"hide"]
	for id: StringName in [&"craft_storage_cache", &"craft_drying_rack", &"craft_bedding"]:
		var recipe := get_node("/root/GameData").get_recipe(id) as RecipeData
		assert_not_null(recipe)
		for ingredient: StringName in recipe.ingredients:
			assert_has(allowed, ingredient)

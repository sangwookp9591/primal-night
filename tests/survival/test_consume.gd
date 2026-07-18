extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func _player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_raw_meat_consumes_one_and_restores_food_from_item_data() -> void:
	var player: Player = _player()
	var raw_meat: ItemData = get_node("/root/GameData").get_item(&"raw_meat")
	player.inventory.add_item(&"raw_meat", 2)
	player.stats.food = 25.0

	assert_true(ConsumeAction.consume(player, raw_meat))

	assert_eq(player.inventory.count_of(&"raw_meat"), 1)
	assert_almost_eq(player.stats.food, 25.0 + raw_meat.nutrition, 0.001)


func test_consume_rejects_missing_or_non_consumable_item() -> void:
	var player: Player = _player()
	var raw_meat: ItemData = get_node("/root/GameData").get_item(&"raw_meat")
	var stone: ItemData = get_node("/root/GameData").get_item(&"stone")

	assert_false(ConsumeAction.consume(player, raw_meat), "보유하지 않은 음식은 먹을 수 없다")
	player.inventory.add_item(&"stone", 1)
	assert_false(ConsumeAction.consume(player, stone), "영양 데이터가 없는 아이템은 먹을 수 없다")
	assert_eq(player.inventory.count_of(&"stone"), 1)


func test_food_restoration_is_capped() -> void:
	var player: Player = _player()
	var raw_meat: ItemData = get_node("/root/GameData").get_item(&"raw_meat")
	player.inventory.add_item(&"raw_meat", 1)
	player.stats.food = 95.0

	assert_true(ConsumeAction.consume(player, raw_meat))

	assert_almost_eq(player.stats.food, SurvivalStats.STAT_MAX, 0.001)


func test_raw_meat_food_poison_roll_is_deterministic() -> void:
	var raw_meat := get_node("/root/GameData").get_item(&"raw_meat") as ItemData
	assert_almost_eq(raw_meat.food_poison_chance, 0.6, 0.001)
	var sick := _player()
	sick.inventory.add_item(&"raw_meat", 1)
	assert_true(ConsumeAction.consume(sick, raw_meat, 0.59))
	assert_gt(sick.stats.food_poison_remaining, 0.0)
	var safe := _player()
	safe.inventory.add_item(&"raw_meat", 1)
	assert_true(ConsumeAction.consume(safe, raw_meat, 0.6))
	assert_eq(safe.stats.food_poison_remaining, 0.0)


func test_toxic_mushroom_applies_poison_immediately() -> void:
	var player := _player()
	var mushroom := get_node("/root/GameData").get_item(&"toxic_mushroom") as ItemData
	player.inventory.add_item(mushroom.id, 1)
	assert_true(ConsumeAction.consume(player, mushroom, 1.0))
	assert_gt(player.stats.poison_remaining, 0.0)
	assert_eq(player.stats.poison_potency, 1.0)
	var health_before := player.health.current_health
	player.stats.simulate(10.0)
	assert_lt(player.health.current_health, health_before)


func test_cooked_dried_and_foraged_food_are_safe() -> void:
	for item_id: StringName in [&"cooked_meat", &"dried_meat", &"berry", &"mushroom"]:
		var player := _player()
		var item := get_node("/root/GameData").get_item(item_id) as ItemData
		player.inventory.add_item(item_id, 1)
		assert_true(ConsumeAction.consume(player, item, 0.0), item_id)
		assert_eq(player.stats.food_poison_remaining, 0.0, item_id)
		assert_eq(player.stats.poison_remaining, 0.0, item_id)


func test_food_safety_snapshot_round_trip_and_death_reset() -> void:
	var source := _player()
	source.stats.apply_food_risk(true, 0.75)
	var snapshot := source.stats.food_safety_snapshot()
	var restored := _player()
	assert_true(restored.stats.apply_food_safety_snapshot(snapshot))
	assert_eq(restored.stats.food_poison_remaining, source.stats.food_poison_remaining)
	assert_eq(restored.stats.poison_remaining, source.stats.poison_remaining)
	assert_eq(restored.stats.poison_potency, source.stats.poison_potency)
	assert_eq(restored.stats._active_state_visual, &"poison_state")
	assert_true(restored.visual_rig.state_overlay.visible)
	assert_true(restored.stats.apply_food_safety_snapshot(snapshot, true))
	assert_eq(restored.stats.food_poison_remaining, 0.0)
	assert_eq(restored.stats.poison_remaining, 0.0)
	assert_eq(restored.stats._active_state_visual, &"")


func test_food_poison_accelerates_drain_and_periodically_emits_vomit_noise() -> void:
	var player := _player()
	player.stats.water = 100.0
	player.stats.food = 100.0
	player.stats.apply_food_risk(true, 0.0)
	watch_signals(get_node("/root/EventBus"))
	player.stats.simulate(SurvivalStats.VOMIT_INTERVAL_SECONDS)
	assert_lt(player.stats.water, 100.0)
	assert_lt(player.stats.food, 100.0)
	assert_signal_emitted(get_node("/root/EventBus"), "noise_emitted")

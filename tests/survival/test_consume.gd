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

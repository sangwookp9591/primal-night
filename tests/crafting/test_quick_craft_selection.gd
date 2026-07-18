extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func _player_with(items: Dictionary) -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	for item_id: StringName in items:
		assert_eq(player.inventory.add_item(item_id, int(items[item_id])), int(items[item_id]))
	return player


func test_quick_craft_selects_first_craftable_recipe_by_priority() -> void:
	var player := _player_with({&"stone": 2, &"wood": 1, &"fiber": 2})

	assert_eq(player.select_quick_craft_recipe(), &"craft_stone_knife",
		"돌칼과 횃불이 모두 가능하면 돌칼을 먼저 선택해야 한다")


func test_quick_craft_falls_through_chain_and_returns_empty_when_none_fit() -> void:
	var lure_player := _player_with({&"bone": 1, &"fiber": 2, &"raw_meat": 1})
	assert_eq(lure_player.select_quick_craft_recipe(), &"craft_noise_lure",
		"상위 세 제작이 불가능하면 소음 미끼를 미끼보다 우선해야 한다")

	var bait_player := _player_with({&"raw_meat": 1})
	assert_eq(bait_player.select_quick_craft_recipe(), &"craft_bait")

	var empty_player := _player_with({})
	assert_eq(empty_player.select_quick_craft_recipe(), &"")

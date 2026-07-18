extends GutTest

const RECIPE_PATHS: Dictionary = {
	&"craft_stone_knife": "res://data/recipes/craft_stone_knife.tres",
	&"craft_torch": "res://data/recipes/craft_torch.tres",
	&"craft_bone_scraper": "res://data/recipes/craft_bone_scraper.tres",
	&"craft_noise_lure": "res://data/recipes/craft_noise_lure.tres",
}


func test_primitive_recipe_resources_define_mvp_chain() -> void:
	var expected: Dictionary = {
		&"craft_stone_knife": {&"stone": 2, &"fiber": 1},
		&"craft_torch": {&"wood": 1, &"fiber": 1},
		&"craft_bone_scraper": {&"bone": 2, &"sinew": 1},
		&"craft_noise_lure": {&"bone": 1, &"fiber": 2},
	}
	for recipe_id: StringName in RECIPE_PATHS:
		var recipe: RecipeData = load(RECIPE_PATHS[recipe_id])
		assert_not_null(recipe, "%s 리소스가 있어야 한다" % recipe_id)
		if recipe == null:
			continue
		assert_eq(recipe.id, recipe_id)
		assert_eq(recipe.ingredients, expected[recipe_id])
		assert_not_null(recipe.result)
		assert_eq(recipe.result.id, StringName(String(recipe_id).trim_prefix("craft_")))
		assert_not_null(recipe.action)
		assert_gt(recipe.action.duration, 0.0)
		assert_gt(recipe.action.noise, 0.0, "제작은 감각 비용을 가져야 한다")
		assert_false(recipe.observation_hint.is_empty(), "재료 관찰문이 있어야 한다")
		assert_false(recipe.observation_success.is_empty(), "성공 관찰문이 있어야 한다")


func test_crafting_each_recipe_consumes_exact_ingredients() -> void:
	# GameData 디렉터리 스캔 작업과 독립적으로 이 워커 소유 리소스/트랜잭션을 검증한다.
	# 통합 시에는 같은 파일들이 자동 등록된다.
	var game_data: Node = get_node("/root/GameData")
	for path: String in [
		"res://data/items/fiber.tres",
		"res://data/items/bone.tres",
		"res://data/items/sinew.tres",
		"res://data/items/stone_knife.tres",
		"res://data/items/torch.tres",
		"res://data/items/bone_scraper.tres",
		"res://data/items/noise_lure.tres",
	]:
		var item: ItemData = load(path)
		game_data._items[item.id] = item
	var player: Player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(player)
	var crafting := Crafting.new()
	add_child_autofree(crafting)
	var event_bus: Node = get_node("/root/EventBus")
	watch_signals(event_bus)

	for recipe_id: StringName in RECIPE_PATHS:
		var recipe: RecipeData = load(RECIPE_PATHS[recipe_id])
		for item_id: StringName in recipe.ingredients:
			assert_eq(player.inventory.add_item(item_id, int(recipe.ingredients[item_id])),
				int(recipe.ingredients[item_id]))
		assert_true(crafting.craft(player, recipe))
		assert_eq(player.inventory.count_of(recipe.result.id), 1)
		for item_id: StringName in recipe.ingredients:
			assert_eq(player.inventory.count_of(item_id), 0)
	assert_signal_emit_count(event_bus, "noise_emitted", RECIPE_PATHS.size(),
		"각 제작 완료는 레시피 ActionDefinition의 감각 비용을 방출해야 한다")

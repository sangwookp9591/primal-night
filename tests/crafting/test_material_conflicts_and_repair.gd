extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const TARGET_MATERIALS: Array[StringName] = [
	&"fiber", &"hide", &"sinew", &"wood", &"stone", &"bone",
]


func test_every_used_material_has_at_least_two_recipe_uses() -> void:
	var uses: Dictionary = {}
	for path: String in GameData.scan_resource_paths("res://data/recipes"):
		var recipe: RecipeData = load(path)
		for ingredient: Variant in recipe.ingredients:
			var item_id := StringName(ingredient)
			if not uses.has(item_id):
				uses[item_id] = []
			uses[item_id].append(recipe.id)
	for item_id: StringName in uses:
		assert_gte((uses[item_id] as Array).size(), 2,
			"전용 재료 %s: %s" % [item_id, uses[item_id]])
	for item_id: StringName in TARGET_MATERIALS:
		assert_true(uses.has(item_id), "%s 재료가 제작 충돌에 참여해야 한다" % item_id)
		if uses.has(item_id):
			assert_gte((uses[item_id] as Array).size(), 2)


func test_new_recipes_are_registered_with_knowledge_observations() -> void:
	var game_data: Node = get_node("/root/GameData")
	for recipe_id: StringName in [&"craft_hide_bait", &"repair_outfit"]:
		var recipe: RecipeData = game_data.get_recipe(recipe_id)
		assert_not_null(recipe, "%s 가 자동 등록되어야 한다" % recipe_id)
		if recipe != null:
			assert_false(recipe.observation_hint.is_empty())
			assert_false(recipe.observation_success.is_empty())


func test_damaged_equipped_outfit_can_be_repaired_with_fiber_and_hide() -> void:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	var crafting := Crafting.new()
	add_child_autofree(crafting)
	var recipe: RecipeData = get_node("/root/GameData").get_recipe(&"repair_outfit")
	assert_not_null(recipe)
	assert_true(recipe.repairs_outfit)
	player.equipment.condition_flags |= EquipmentComponent.DAMAGED_FLAG
	assert_eq(player.inventory.add_item(&"fiber", 2), 2)
	assert_eq(player.inventory.add_item(&"hide", 1), 1)
	assert_eq(player.select_quick_craft_recipe(), &"repair_outfit")
	assert_true(crafting.craft(player, recipe))
	assert_eq(player.equipment.condition_flags & EquipmentComponent.DAMAGED_FLAG, 0)
	assert_eq(player.inventory.count_of(&"fiber"), 0)
	assert_eq(player.inventory.count_of(&"hide"), 0)


func test_repair_rejects_undamaged_outfit_without_consuming_materials() -> void:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	var crafting := Crafting.new()
	add_child_autofree(crafting)
	var recipe: RecipeData = get_node("/root/GameData").get_recipe(&"repair_outfit")
	assert_eq(player.inventory.add_item(&"fiber", 2), 2)
	assert_eq(player.inventory.add_item(&"hide", 1), 1)
	assert_false(crafting.craft(player, recipe))
	assert_eq(player.inventory.count_of(&"fiber"), 2)
	assert_eq(player.inventory.count_of(&"hide"), 1)
	assert_ne(player.select_quick_craft_recipe(), &"repair_outfit")


func test_one_full_raptor_yield_supports_each_rebalanced_single_choice() -> void:
	var profile: CarcassProfile = load("res://data/creatures/carcass_raptor.tres")
	var totals: Dictionary = {}
	for stage: int in range(profile.stage_count):
		for item_id: Variant in profile.yields_for_stage(stage):
			totals[item_id] = int(totals.get(item_id, 0)) \
				+ int(profile.yields_for_stage(stage)[item_id])
	assert_gte(int(totals.get(&"hide", 0)), 1)
	assert_gte(int(totals.get(&"sinew", 0)), 1)
	assert_gte(int(totals.get(&"bone", 0)), 2)
	assert_lte(get_node("/root/GameData").get_recipe(&"craft_bow").ingredients[&"sinew"],
		int(totals[&"sinew"]))


func test_specialized_outfit_recipes_consume_competing_materials() -> void:
	var expected := {
		&"craft_fur_cloak": {&"hide": 3, &"sinew": 2},
		&"craft_reed_raincoat": {&"fiber": 4, &"wood": 1},
		&"craft_bone_armor": {&"bone": 3, &"sinew": 2, &"hide": 1},
	}
	for recipe_id: StringName in expected:
		var player := PlayerScene.instantiate() as Player
		add_child_autofree(player)
		var crafting := Crafting.new()
		add_child_autofree(crafting)
		var recipe := get_node("/root/GameData").get_recipe(recipe_id) as RecipeData
		assert_not_null(recipe, recipe_id)
		assert_eq(recipe.ingredients, expected[recipe_id], recipe_id)
		for item_id: StringName in expected[recipe_id]:
			assert_eq(player.inventory.add_item(item_id, expected[recipe_id][item_id]),
				expected[recipe_id][item_id])
		assert_true(crafting.craft(player, recipe), recipe_id)
		assert_eq(player.inventory.count_of(recipe.result.id), 1, recipe_id)
		assert_true(player.equipment.request_equip(recipe.result.id), recipe_id)
		assert_eq(player.equipment.get_equipped(&"outfit"), recipe.result.id, recipe_id)
		assert_true(player.visual_rig.outfit.visible, recipe_id)
		assert_not_null(player.visual_rig.outfit.sprite_frames, recipe_id)

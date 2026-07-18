extends GutTest
func test_unknown_recipe_is_rejected() -> void:
	var c := Crafting.new(); add_child_autofree(c); assert_false(c.craft(null, null))

func test_recipe_requires_actor_and_recipe() -> void:
	var c := Crafting.new(); add_child_autofree(c)
	var actor: Node = add_child_autofree(Node.new())
	assert_false(c.craft(actor, null))

func test_bait_craft_consumes_material_once() -> void:
	var player: Player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(player)
	var c := Crafting.new(); add_child_autofree(c)
	player.inventory.add_item(&"raw_meat", 1)
	assert_true(c.craft(player, get_node("/root/GameData").get_recipe(&"craft_bait")))
	assert_eq(player.inventory.count_of(&"raw_meat"), 0)
	assert_eq(player.inventory.count_of(&"bait"), 1)

func test_small_pack_recipe_consumes_competing_materials() -> void:
	var player: Player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(player)
	var crafting := Crafting.new()
	add_child_autofree(crafting)
	var recipe: RecipeData = get_node("/root/GameData").get_recipe(&"craft_small_pack")
	assert_not_null(recipe)
	player.inventory.add_item(&"hide", 2)
	player.inventory.add_item(&"fiber", 3)
	player.inventory.add_item(&"sinew", 1)

	assert_true(crafting.craft(player, recipe))
	assert_eq(player.inventory.count_of(&"hide"), 0)
	assert_eq(player.inventory.count_of(&"fiber"), 0)
	assert_eq(player.inventory.count_of(&"sinew"), 0)
	assert_eq(player.inventory.count_of(&"small_pack"), 1)

func test_missing_material_slot_and_weight_fail_without_mutation() -> void:
	var player: Player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(player)
	var c := Crafting.new(); add_child_autofree(c)
	var recipe: RecipeData = get_node("/root/GameData").get_recipe(&"craft_bait")
	assert_false(c.craft(player, recipe))
	assert_eq(player.inventory.count_of(&"bait"), 0)

	player.inventory.add_item(&"raw_meat", 1)
	player.inventory.add_item(&"stone", 19)
	assert_true(c.craft(player, recipe), "재료 제거 뒤 빈 무게/슬롯으로 결과가 들어가야 한다")
	assert_eq(player.inventory.count_of(&"raw_meat"), 0)
	assert_eq(player.inventory.count_of(&"bait"), 1)

	var slot_blocked: Player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(slot_blocked)
	slot_blocked.inventory.max_weight = 400.0
	assert_eq(slot_blocked.inventory.add_item(&"stone", 300), 300)
	assert_eq(slot_blocked.inventory.add_item(&"raw_meat", 2), 2)
	assert_false(c.craft(slot_blocked, recipe))
	assert_eq(slot_blocked.inventory.count_of(&"raw_meat"), 2, "실패한 제작은 재료를 보존해야 한다")
	assert_eq(slot_blocked.inventory.count_of(&"bait"), 0)

	var blocked: Player = preload("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(blocked)
	blocked.inventory.add_item(&"raw_meat", 1)
	blocked.inventory.max_weight = 0.25
	assert_false(c.craft(blocked, recipe))
	assert_eq(blocked.inventory.count_of(&"raw_meat"), 1, "실패한 제작은 재료를 보존해야 한다")
	assert_eq(blocked.inventory.count_of(&"bait"), 0)

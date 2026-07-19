extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CampfireSiteScene: PackedScene = preload("res://scenes/props/campfire_site.tscn")


func _player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_water_source_drinks_or_fills_a_two_use_waterskin() -> void:
	var player := _player()
	var source := WaterSource.new()
	add_child_autofree(source)
	player.stats.water = 10.0
	source.interact(player)
	assert_eq(player.stats.water, 45.0)
	player.inventory.add_item(&"waterskin", 1)
	assert_true(source.fill_waterskin(player))
	assert_eq(player.inventory.count_of(&"waterskin_full"), 1)
	var full: ItemData = load("res://data/items/waterskin_full.tres")
	var half: ItemData = load("res://data/items/waterskin_half.tres")
	assert_true(ConsumeAction.consume(player, full, 1.0))
	assert_eq(player.inventory.count_of(&"waterskin_half"), 1)
	assert_true(ConsumeAction.consume(player, half, 1.0))
	assert_eq(player.inventory.count_of(&"waterskin"), 1)


func test_antidote_salad_halves_both_food_safety_states() -> void:
	var player := _player()
	var salad: ItemData = load("res://data/items/antidote_salad.tres")
	player.inventory.add_item(&"antidote_salad", 1)
	player.stats.food_poison_remaining = 80.0
	player.stats.poison_remaining = 40.0
	assert_true(ConsumeAction.consume(player, salad, 1.0))
	assert_eq(player.stats.food_poison_remaining, 40.0)
	assert_eq(player.stats.poison_remaining, 20.0)


func test_lit_campfire_cooks_soup_and_returns_remaining_water_charge() -> void:
	var player := _player()
	var site: CampfireSite = CampfireSiteScene.instantiate()
	add_child_autofree(site)
	site.build_and_light()
	player.inventory.add_item(&"bone", 2)
	player.inventory.add_item(&"waterskin_full", 1)
	assert_eq(site.cook_kind(player), &"marrow_soup")
	assert_true(site.apply_cook(player))
	assert_eq(player.inventory.count_of(&"bone"), 0)
	assert_eq(player.inventory.count_of(&"marrow_soup"), 1)
	assert_eq(player.inventory.count_of(&"waterskin_half"), 1)


func test_soup_restores_food_water_and_temperature() -> void:
	var player := _player()
	var soup: ItemData = load("res://data/items/marrow_soup.tres")
	player.inventory.add_item(&"marrow_soup", 1)
	player.stats.food = 10.0
	player.stats.water = 10.0
	player.stats.temperature = 10.0
	assert_true(ConsumeAction.consume(player, soup, 1.0))
	assert_eq(player.stats.food, 65.0)
	assert_eq(player.stats.water, 25.0)
	assert_eq(player.stats.temperature, 35.0)


func test_new_atlas_contract_preserves_food_cells_inside_29_cell_sheet() -> void:
	assert_eq(WorldItem.ITEM_SHEET.get_size(), Vector2(1856, 128))
	assert_eq(WorldItem.atlas_index_for(&"waterskin"), 20)
	assert_eq(WorldItem.atlas_index_for(&"herb"), 21)
	assert_eq(WorldItem.atlas_index_for(&"antidote_salad"), 22)
	assert_eq(WorldItem.atlas_index_for(&"marrow_soup"), 23)
	assert_eq(WorldItem.atlas_index_for(&"tallow"), 24)

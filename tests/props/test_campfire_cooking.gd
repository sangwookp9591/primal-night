extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const SiteScene: PackedScene = preload("res://scenes/props/campfire_site.tscn")


func _setup_pair() -> Dictionary:
	var root: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var player: Player = PlayerScene.instantiate()
	root.add_child(player)
	var site: CampfireSite = SiteScene.instantiate()
	site.position = Vector2(24.0, 0.0)
	root.add_child(site)
	site.build_and_light()
	return {player = player, site = site}


func test_lit_fire_converts_one_raw_meat_transactionally() -> void:
	var pair := _setup_pair()
	var player: Player = pair.player
	var site: CampfireSite = pair.site
	player.inventory.add_item(&"raw_meat", 2)
	assert_true(site.can_interact(player))
	assert_eq(site.get_prompt(), "고기 굽기")
	assert_eq(site.get_hold_seconds(), 3.0)
	assert_true(site.apply_cook(player))
	assert_eq(player.inventory.count_of(&"raw_meat"), 1)
	assert_eq(player.inventory.count_of(&"cooked_meat"), 1)


func test_extinguished_fire_rejects_cooking_without_consumption() -> void:
	var pair := _setup_pair()
	var player: Player = pair.player
	var site: CampfireSite = pair.site
	player.inventory.add_item(&"raw_meat", 1)
	site.campfire.extinguish()
	assert_false(site.can_interact(player))
	assert_false(site.apply_cook(player))
	assert_eq(player.inventory.count_of(&"raw_meat"), 1)
	assert_eq(player.inventory.count_of(&"cooked_meat"), 0)


func test_cooking_hold_registers_cooked_meat_smell_until_hold_ends() -> void:
	var pair := _setup_pair()
	var player: Player = pair.player
	var site: CampfireSite = pair.site
	player.inventory.add_item(&"raw_meat", 1)
	site.on_hold_started(player)
	assert_true(site.has_cooking_smell())
	var source := site.get_node("CookingSmell") as SmellSource
	assert_eq(source.kind, &"cooked_meat")
	assert_eq(source.strength, 15.0)
	site.on_hold_ended(player)
	assert_false(site.has_cooking_smell())

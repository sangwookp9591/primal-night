extends GutTest

const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")
const InventoryScreenScene: PackedScene = preload("res://scenes/ui/inventory/inventory_screen.tscn")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

const EXPECTED_INDICES := {
	&"stone": 0,
	&"wood": 1,
	&"fiber": 2,
	&"bone": 3,
	&"sinew": 4,
	&"raw_meat": 5,
	&"bandage": 6,
	&"bait": 7,
	&"smartphone": 8,
	&"stone_knife": 9,
	&"torch": 10,
	&"bone_scraper": 11,
	&"noise_lure": 12,
	&"hide": 13,
	&"berry": 14,
	&"mushroom": 15,
	&"toxic_mushroom": 16,
	&"cooked_meat": 17,
	&"bone_flute": 18,
	&"bait_pouch": 19,
	&"waterskin": 20,
	&"herb": 21,
	&"antidote_salad": 22,
	&"marrow_soup": 23,
	&"tallow": 24,
}


func test_all_item_ids_map_to_the_documented_atlas_cells() -> void:
	assert_eq(WorldItem.ITEM_ATLAS_INDICES.size(), 25)
	for id: StringName in EXPECTED_INDICES:
		var index: int = EXPECTED_INDICES[id]
		assert_eq(WorldItem.atlas_index_for(id), index, String(id))
		var texture := WorldItem.icon_texture(id)
		assert_not_null(texture, String(id))
		assert_eq(texture.region, Rect2(index * 64.0, 0.0, 64.0, 128.0), String(id))
	assert_eq(WorldItem.atlas_index_for(&"unknown"), -1)
	assert_null(WorldItem.icon_texture(&"unknown"))
	assert_eq((WorldItem.ITEM_SHEET as Texture2D).get_width(), 1600)


func test_world_item_scene_uses_atlas_sprite_and_hides_placeholder() -> void:
	var item: WorldItem = WorldItemScene.instantiate()
	item.item_id = &"bone_scraper"
	add_child_autofree(item)
	await wait_process_frames(1)

	var sprite := item.get_node("ItemSprite") as Sprite2D
	assert_not_null(sprite)
	assert_true(sprite.texture is AtlasTexture)
	assert_eq((sprite.texture as AtlasTexture).region, Rect2(704.0, 0.0, 64.0, 128.0))
	assert_false((item.get_node("Marker") as ColorRect).visible)


func test_inventory_slot_reuses_the_world_item_icon() -> void:
	var root: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var player: Player = PlayerScene.instantiate()
	root.add_child(player)
	var screen: InventoryScreen = InventoryScreenScene.instantiate()
	root.add_child(screen)
	await wait_process_frames(1)
	screen.bind(player)
	player.inventory.add_item(&"sinew", 1)

	var texture := screen.slot_icon(0) as AtlasTexture
	assert_not_null(texture)
	assert_eq(texture.region, Rect2(256.0, 0.0, 64.0, 128.0))

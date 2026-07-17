extends GutTest

const CampfireScene: PackedScene = preload("res://scenes/props/campfire.tscn")
const CampfireSiteScene: PackedScene = preload("res://scenes/props/campfire_site.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")


func test_campfire_scene_uses_unlit_and_three_frame_lit_animation() -> void:
	var campfire: Campfire = CampfireScene.instantiate()
	add_child_autofree(campfire)
	var sprite := campfire.get_node("CampfireSprite") as AnimatedSprite2D

	assert_not_null(sprite)
	assert_eq(sprite.animation, &"unlit")
	assert_eq(sprite.sprite_frames.get_frame_count(&"unlit"), 1)
	assert_eq(sprite.sprite_frames.get_frame_count(&"lit"), 3)
	assert_false((campfire.get_node("Flame") as ColorRect).visible)

	campfire.light()
	assert_eq(sprite.animation, &"lit")
	assert_true(sprite.is_playing())
	campfire.extinguish()
	assert_eq(sprite.animation, &"unlit")


func test_campfire_site_uses_unlit_atlas_cell_and_hides_ring() -> void:
	var site: CampfireSite = CampfireSiteScene.instantiate()
	add_child_autofree(site)
	var sprite := site.get_node("SiteSprite") as Sprite2D

	assert_not_null(sprite)
	assert_true(sprite.texture is AtlasTexture)
	assert_eq((sprite.texture as AtlasTexture).region, Rect2(0.0, 0.0, 128.0, 128.0))
	assert_false((site.get_node("Ring") as ColorRect).visible)


func test_main_scene_instances_world_item_and_campfire_visual_contracts() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await wait_process_frames(1)

	var item := main.get_node("SurvivalDemo/Stone1") as WorldItem
	var site := main.get_node("SurvivalDemo/CampfireSite") as CampfireSite
	assert_not_null(item)
	assert_not_null(item.get_node("ItemSprite").texture)
	assert_not_null(site)
	assert_not_null(site.get_node("SiteSprite").texture)

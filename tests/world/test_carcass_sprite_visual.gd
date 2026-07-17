extends GutTest

const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const CarcassSheet: Texture2D = preload("res://assets/sprites/creatures/raptor_carcass_stages_sheet.png")
const VisualScript = preload("res://scripts/world/carcass_sprite_visual.gd")


func test_stage_for_progress_maps_four_art_rows_to_full_butcher_progress() -> void:
	assert_eq(VisualScript.stage_for_progress(0, 4), VisualScript.Stage.INTACT)
	assert_eq(VisualScript.stage_for_progress(1, 4), VisualScript.Stage.PARTIAL)
	assert_eq(VisualScript.stage_for_progress(2, 4), VisualScript.Stage.MOSTLY)
	assert_eq(VisualScript.stage_for_progress(3, 4), VisualScript.Stage.MOSTLY)
	assert_eq(VisualScript.stage_for_progress(4, 4), VisualScript.Stage.COMPLETE)


func test_atlas_frame_uses_direction_columns_and_stage_rows() -> void:
	var frame: AtlasTexture = VisualScript.atlas_frame(
		VisualScript.Direction.SW,
		VisualScript.Stage.MOSTLY)

	assert_eq(frame.atlas, CarcassSheet)
	assert_eq(frame.region, Rect2(Vector2(5 * 64, 2 * 64), Vector2(64, 64)))


func test_real_carcass_scene_loads_sheet_and_hides_gray_box_marker() -> void:
	var carcass: Carcass = add_child_autofree(CarcassScene.instantiate())
	await wait_physics_frames(1)
	var visual: Sprite2D = carcass.get_node("SpriteVisual") as Sprite2D
	var marker: ColorRect = carcass.get_node("Marker") as ColorRect

	assert_not_null(visual)
	assert_false(marker.visible, "gray-box ColorRect remains only as a hidden compatibility node")
	assert_eq(CarcassSheet.get_size(), Vector2(512.0, 256.0))
	assert_eq(visual.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(visual.offset, Vector2(0.0, -32.0))
	assert_eq((visual.texture as AtlasTexture).region,
		Rect2(Vector2(VisualScript.Direction.S * 64, 0), Vector2(64, 64)))


func test_carcass_visual_stage_follows_butcher_mask() -> void:
	var carcass: Carcass = add_child_autofree(CarcassScene.instantiate())
	await wait_physics_frames(1)
	var visual: Sprite2D = carcass.get_node("SpriteVisual") as Sprite2D

	carcass.apply_replicated_mask(0b0001)
	assert_eq(carcass.visual_stage(), VisualScript.Stage.PARTIAL)
	assert_eq((visual.texture as AtlasTexture).region.position.y, 64.0)

	carcass.apply_replicated_mask(0b0111)
	assert_eq(carcass.visual_stage(), VisualScript.Stage.MOSTLY)
	assert_eq((visual.texture as AtlasTexture).region.position.y, 128.0)

	carcass.apply_replicated_mask(0b1111)
	assert_eq(carcass.visual_stage(), VisualScript.Stage.COMPLETE)
	assert_eq((visual.texture as AtlasTexture).region.position.y, 192.0)


func test_main_scene_seeded_carcass_has_sprite_visual() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(1)
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass") as Carcass

	assert_not_null(carcass.get_node_or_null("SpriteVisual"))

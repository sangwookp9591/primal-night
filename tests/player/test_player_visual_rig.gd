extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SHEET_VISUAL_IDS: Array[StringName] = [
	&"white_underwear",
	&"work_clothes",
	&"leather_armor",
	&"placeholder_back",
	&"stone_knife",
	&"stone_spear",
	&"bow",
	&"torch",
]


func test_registered_visuals_have_all_direction_action_frame_keys() -> void:
	for visual_id: StringName in PlayerVisualProfile.registered_visual_ids():
		assert_true(PlayerVisualProfile.has_complete_frame_keys(visual_id), visual_id)


func test_equipment_sheets_register_48_atlas_frames_per_visual() -> void:
	for visual_id: StringName in SHEET_VISUAL_IDS:
		assert_true(PlayerVisualProfile.has_registered_sheet(visual_id), visual_id)
		var frames := PlayerVisualProfile.build_frames(visual_id)
		var frame_total := 0
		for direction: int in range(PlayerVisualProfile.DIRECTION_COUNT):
			for walking: bool in [false, true]:
				var animation := PlayerSpriteAnimator.animation_name(walking, direction)
				frame_total += frames.get_frame_count(animation)
				for frame_index: int in range(frames.get_frame_count(animation)):
					assert_is(frames.get_frame_texture(animation, frame_index), AtlasTexture, visual_id)
		assert_eq(frame_total, 48, visual_id)


func test_player_and_equipment_sheets_match_six_frame_atlas_contract() -> void:
	var sheet_paths: Array[String] = [
		"res://assets/sprites/player/player_survivor_sheet.png",
	]
	for visual_id: StringName in SHEET_VISUAL_IDS:
		sheet_paths.append(String(PlayerVisualProfile.VISUALS[visual_id].sheet))
	for sheet_path: String in sheet_paths:
		var texture := load(sheet_path) as Texture2D
		assert_not_null(texture, sheet_path)
		var image := texture.get_image()
		assert_eq(image.get_size(), Vector2i(
			PlayerVisualProfile.CELL_SIZE.x * PlayerVisualProfile.DIRECTION_COUNT,
			PlayerVisualProfile.CELL_SIZE.y * 6), sheet_path)
		for row: int in range(6):
			for direction: int in range(PlayerVisualProfile.DIRECTION_COUNT):
				var centroid := _alpha_centroid(image, direction, row)
				assert_between(centroid.x, 0.0, float(PlayerVisualProfile.CELL_SIZE.x - 1),
					"%s d%d f%d x" % [sheet_path, direction, row])
				assert_between(centroid.y, 0.0, float(PlayerVisualProfile.CELL_SIZE.y - 1),
					"%s d%d f%d y" % [sheet_path, direction, row])


func test_player_sheets_contain_no_magenta_key_pixels() -> void:
	var sheet_paths: Array[String] = [
		"res://assets/sprites/player/player_survivor_sheet.png",
	]
	for visual_id: StringName in SHEET_VISUAL_IDS:
		sheet_paths.append(String(PlayerVisualProfile.VISUALS[visual_id].sheet))
	for sheet_path: String in sheet_paths:
		# Inspect the authored PNG bytes directly. Texture import converts sRGB
		# channels to linear values, which changes channel ratios despite leaving
		# the visible source pixel unchanged.
		var image := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
		image.convert(Image.FORMAT_RGBA8)
		var bytes := image.get_data()
		var magenta_pixels := 0
		for byte_index: int in range(0, bytes.size(), 4):
			var red := bytes[byte_index]
			var green := bytes[byte_index + 1]
			var blue := bytes[byte_index + 2]
			var alpha := bytes[byte_index + 3]
			if alpha > 0 \
					and red > 60 \
					and blue > 50 \
					and red > green * 1.35 \
					and blue > green * 1.35:
				magenta_pixels += 1
		assert_eq(magenta_pixels, 0, "%s has magenta key fringe" % sheet_path)


func test_base_body_does_not_contain_baked_russet_clothing_palette() -> void:
	var sheet_path := "res://assets/sprites/player/player_survivor_sheet.png"
	var image := Image.load_from_file(ProjectSettings.globalize_path(sheet_path))
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	var russet_pixels := 0
	for byte_index: int in range(0, bytes.size(), 4):
		var red := bytes[byte_index]
		var green := bytes[byte_index + 1]
		var blue := bytes[byte_index + 2]
		var alpha := bytes[byte_index + 3]
		if alpha > 0 and red >= 70 and red <= 170 \
				and green < 80 and blue < 80 \
				and red > green * 1.45:
			russet_pixels += 1
	# A few face-shadow pixels share this broad hue band; a baked jacket produced
	# more than a thousand. Keep the allowance below two pixels per atlas cell.
	assert_lte(russet_pixels, 64, "BaseBody contains baked jacket/backpack palette")


func test_equipment_overlay_centroids_stay_in_anatomical_bands() -> void:
	var outfit_ids: Array[StringName] = [
		&"white_underwear", &"work_clothes", &"leather_armor",
	]
	var hand_ids: Array[StringName] = [&"stone_knife", &"stone_spear", &"bow", &"torch"]
	for visual_id: StringName in outfit_ids + hand_ids:
		var texture := load(String(PlayerVisualProfile.VISUALS[visual_id].sheet)) as Texture2D
		var image := texture.get_image()
		assert_false(image.is_empty(), visual_id)
		for row: int in range(6):
			for direction: int in range(8):
				var centroid := _alpha_centroid(image, direction, row)
				assert_between(centroid.x, 5.0, 43.0, "%s d%d f%d x" % [
					visual_id, direction, row])
				if visual_id in outfit_ids:
					assert_between(centroid.y, 18.0, 42.0, "%s d%d f%d torso y" % [
						visual_id, direction, row])
				else:
					assert_between(centroid.y, 18.0, 46.0, "%s d%d f%d hand y" % [
						visual_id, direction, row])


func test_visual_layers_share_base_body_anchor() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var rig: PlayerVisualRig = player.get_node("VisualRig")
	for layer_name: StringName in [&"outfit", &"back", &"main_hand", &"state_overlay"]:
		var layer := rig.get_layer(layer_name)
		assert_eq(layer.offset, rig.base_body.offset, layer_name)
		assert_eq(layer.centered, rig.base_body.centered, layer_name)


func test_placeholder_visuals_keep_generated_fallback_textures() -> void:
	for visual_id: StringName in [&"placeholder_main_hand", &"placeholder_state_overlay"]:
		assert_false(PlayerVisualProfile.has_registered_sheet(visual_id), visual_id)
		var frames := PlayerVisualProfile.build_frames(visual_id)
		assert_is(frames.get_frame_texture(&"idle_S", 0), ImageTexture, visual_id)


func test_layers_copy_owner_animation_and_frame_in_same_tick() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var rig: PlayerVisualRig = player.get_node("VisualRig")
	assert_true(rig.apply_visual(&"back", &"placeholder_back"))
	assert_true(rig.apply_visual(&"main_hand", &"placeholder_main_hand"))
	assert_true(rig.apply_visual(&"state_overlay", &"placeholder_state_overlay"))

	rig.update_from_velocity(Vector2.RIGHT, 0)
	rig.base_body.set_frame_and_progress(2, 0.5)
	rig._sync_layers()
	for layer_name: StringName in [&"outfit", &"back", &"main_hand", &"state_overlay"]:
		var layer := rig.get_layer(layer_name)
		assert_eq(layer.animation, rig.base_body.animation, layer_name)
		assert_eq(layer.frame, rig.base_body.frame, layer_name)
		assert_eq(layer.frame_progress, rig.base_body.frame_progress, layer_name)


func test_direction_z_order_table_is_complete_and_applied() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var rig: PlayerVisualRig = player.get_node("VisualRig")
	for direction: int in range(PlayerSpriteAnimator.DIRECTION_COUNT):
		var rule := PlayerVisualProfile.z_order(direction)
		assert_eq(rule.size(), 5)
		rig.base_body.last_direction = direction
		rig._sync_layers()
		assert_eq(rig.back.z_index, rule.back, PlayerSpriteAnimator.direction_name(direction))
		if direction in [
			PlayerSpriteAnimator.Direction.N,
			PlayerSpriteAnimator.Direction.NE,
			PlayerSpriteAnimator.Direction.NW,
		]:
			assert_gt(rig.back.z_index, rig.base_body.z_index)
		else:
			assert_lt(rig.back.z_index, rig.base_body.z_index)


func test_missing_visual_hides_layer_without_crashing() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var rig: PlayerVisualRig = player.get_node("VisualRig")
	assert_true(rig.apply_visual(&"back", &"placeholder_back"))
	assert_true(rig.back.visible)
	assert_false(rig.apply_visual(&"back", &"does_not_exist"))
	assert_false(rig.back.visible)
	assert_null(rig.back.sprite_frames)


func test_equipment_signal_toggles_outfit_layer() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var rig: PlayerVisualRig = player.get_node("VisualRig")
	var equipment: EquipmentComponent = player.get_node("EquipmentComponent")
	assert_eq(equipment.get_equipped(&"outfit"), &"white_underwear")
	assert_true(rig.outfit.visible)
	assert_not_null(rig.outfit.sprite_frames)

	equipment.equipment_changed.emit(&"outfit", &"")
	assert_false(rig.outfit.visible)
	equipment.equipment_changed.emit(&"outfit", &"white_underwear")
	assert_true(rig.outfit.visible)


func test_equipping_small_pack_applies_placeholder_back_visual() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	var rig: PlayerVisualRig = player.get_node("VisualRig")

	assert_eq(player.inventory.add_item(&"small_pack", 1), 1)
	assert_true(player.equipment.request_equip(&"small_pack"))
	assert_eq(player.equipment.get_equipped(&"back"), &"small_pack")
	assert_true(rig.back.visible)
	assert_not_null(rig.back.sprite_frames)
	assert_is(rig.back.sprite_frames.get_frame_texture(&"idle_S", 0), AtlasTexture)


func _alpha_centroid(image: Image, column: int, row: int) -> Vector2:
	var weighted := Vector2.ZERO
	var total_alpha := 0.0
	for y: int in range(PlayerVisualProfile.CELL_SIZE.y):
		for x: int in range(PlayerVisualProfile.CELL_SIZE.x):
			var alpha := image.get_pixel(
				column * PlayerVisualProfile.CELL_SIZE.x + x,
				row * PlayerVisualProfile.CELL_SIZE.y + y).a
			weighted += Vector2(x, y) * alpha
			total_alpha += alpha
	assert_gt(total_alpha, 0.0, "overlay cell must not be empty")
	return weighted / total_alpha

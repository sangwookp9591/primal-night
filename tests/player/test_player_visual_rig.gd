extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")


func test_registered_visuals_have_all_direction_action_frame_keys() -> void:
	for visual_id: StringName in PlayerVisualProfile.registered_visual_ids():
		assert_true(PlayerVisualProfile.has_complete_frame_keys(visual_id), visual_id)


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

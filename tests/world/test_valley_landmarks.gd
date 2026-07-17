extends GutTest

const ValleyScene: PackedScene = preload("res://scenes/world/valley.tscn")
const LandmarkScript = preload("res://scripts/world/landmark_visual.gd")
const LandmarkSheet: Texture2D = preload("res://assets/sprites/landmarks/valley_landmarks_10_sheet.png")


func _make_valley() -> ValleyMap:
	var valley: ValleyMap = ValleyScene.instantiate()
	add_child_autofree(valley)
	return valley


func test_s_landmark_sheet_indices_are_row_major_s01_to_s10() -> void:
	for index: int in range(10):
		var landmark_id := "S%02d" % (index + 1)
		var expected := Rect2(Vector2((index % 5) * 128, (index / 5) * 128), Vector2(128, 128))

		assert_eq(LandmarkScript.sheet_index_for(landmark_id), index)
		assert_eq(LandmarkScript.atlas_region_for(landmark_id), expected)


func test_valley_scene_replaces_s_landmarks_with_sprite_cells() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(2)
	var landmarks: Node2D = valley.get_node("Landmarks")

	assert_eq(LandmarkSheet.get_size(), Vector2(640.0, 256.0))
	for index: int in range(10):
		var landmark_id := "S%02d" % (index + 1)
		var marker: Node2D = landmarks.get_node(landmark_id) as Node2D
		var sprite: Sprite2D = marker.get_node("Sprite") as Sprite2D
		var label: Label = marker.get_node("Label") as Label
		var atlas: AtlasTexture = sprite.texture as AtlasTexture

		assert_not_null(sprite, "%s must use a sprite cell" % landmark_id)
		assert_not_null(label, "%s label remains visible" % landmark_id)
		assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_eq(sprite.offset, Vector2(0.0, -64.0), "sprite origin is bottom-center foot point")
		assert_eq(atlas.atlas, LandmarkSheet)
		assert_eq(atlas.region, LandmarkScript.atlas_region_for(landmark_id))
		assert_true(label.text.begins_with(landmark_id))


func test_auxiliary_anchors_remain_simple_markers() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(2)
	var landmarks: Node2D = valley.get_node("Landmarks")

	for landmark_id: String in ["F1", "F2", "F3", "R1", "R2", "H1"]:
		var marker: Node2D = landmarks.get_node(landmark_id) as Node2D
		assert_not_null(marker.get_node_or_null("Marker"), "%s keeps the simple marker" % landmark_id)
		assert_not_null(marker.get_node_or_null("Label"), "%s keeps its label" % landmark_id)
		assert_null(marker.get_node_or_null("Sprite"), "%s is not part of the S01-S10 prop sheet" % landmark_id)


func test_landmark_scene_preserves_public_subtree_contract() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(2)
	var landmarks: Node2D = valley.get_node("Landmarks")

	assert_true(landmarks.y_sort_enabled)
	assert_eq(landmarks.get_child_count(), 16)
	for landmark_id: String in LandmarkScript.LANDMARKS:
		var marker: Node2D = landmarks.get_node_or_null(landmark_id) as Node2D
		assert_not_null(marker, "%s remains a direct Landmarks child" % landmark_id)
		assert_eq(marker.global_position, valley.landmark_world_position(landmark_id))

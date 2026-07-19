extends GutTest

const RaptorScene: PackedScene = preload("res://scenes/creature/raptor.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const RaptorSheet: Texture2D = preload("res://assets/sprites/creatures/raptor_idle_walk_sheet.png")
const AnimatorScript = preload("res://scripts/creature/raptor_sprite_animator.gd")


func test_direction_for_vector_uses_eight_45_degree_sectors() -> void:
	var cases: Array[Dictionary] = [
		{ vector = Vector2.UP, direction = AnimatorScript.Direction.N },
		{ vector = Vector2(1.0, -1.0), direction = AnimatorScript.Direction.NE },
		{ vector = Vector2.RIGHT, direction = AnimatorScript.Direction.E },
		{ vector = Vector2(1.0, 1.0), direction = AnimatorScript.Direction.SE },
		{ vector = Vector2.DOWN, direction = AnimatorScript.Direction.S },
		{ vector = Vector2(-1.0, 1.0), direction = AnimatorScript.Direction.SW },
		{ vector = Vector2.LEFT, direction = AnimatorScript.Direction.W },
		{ vector = Vector2(-1.0, -1.0), direction = AnimatorScript.Direction.NW },
	]
	for item: Dictionary in cases:
		assert_eq(AnimatorScript.direction_for_vector(item.vector), item.direction)


func test_sprite_frames_contain_all_directional_idle_and_walk_animations() -> void:
	var frames: SpriteFrames = AnimatorScript.build_sprite_frames()
	for direction: int in range(AnimatorScript.DIRECTION_COUNT):
		var idle: StringName = AnimatorScript.animation_name(false, direction)
		var walk: StringName = AnimatorScript.animation_name(true, direction)
		assert_true(frames.has_animation(idle), "missing %s" % idle)
		assert_true(frames.has_animation(walk), "missing %s" % walk)
		assert_eq(frames.get_frame_count(idle), 2)
		assert_eq(frames.get_frame_count(walk), 4)


func test_real_raptor_scene_loads_sheet_and_hides_gray_box() -> void:
	var raptor: Raptor = add_child_autofree(RaptorScene.instantiate())
	await wait_physics_frames(1)
	var animator: AnimatedSprite2D = raptor.get_node("SpriteAnimator") as AnimatedSprite2D
	var body: ColorRect = raptor.get_node("Body") as ColorRect

	assert_not_null(animator)
	assert_false(body.visible, "gray-box ColorRect remains only as a hidden compatibility node")
	assert_eq(RaptorSheet.get_size(), Vector2(768.0, 480.0))
	assert_eq(animator.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(animator.offset, Vector2(0.0, -40.0))
	assert_eq(animator.sprite_frames.get_frame_texture(&"idle_S", 0).get_size(), Vector2(96.0, 80.0))
	assert_eq(animator.animation, &"idle_S")


func test_raptor_visual_updates_for_walk_chase_and_idle_last_direction() -> void:
	var animator: AnimatedSprite2D = AnimatorScript.new()
	add_child_autofree(animator)
	await wait_physics_frames(1)

	animator.update_from_velocity(Vector2.RIGHT * 55.0, Raptor.State.WANDER)
	assert_eq(animator.animation, &"walk_E")
	assert_eq(animator.speed_scale, 1.0)

	animator.update_from_velocity(Vector2.RIGHT * 200.0, Raptor.State.CHASE)
	assert_eq(animator.animation, &"walk_E")
	assert_almost_eq(animator.speed_scale, AnimatorScript.CHASE_SPEED_SCALE, 0.001)

	animator.update_from_velocity(Vector2.ZERO, Raptor.State.CHASE)
	assert_eq(animator.animation, &"idle_E")
	assert_eq(animator.speed_scale, 1.0)


func test_walk_frames_advance_and_have_distinct_authored_pixels() -> void:
	var animator := AnimatorScript.new() as RaptorSpriteAnimator
	add_child_autofree(animator)
	await wait_physics_frames(1)
	animator.update_from_velocity(Vector2.RIGHT * 55.0, Raptor.State.WANDER)
	var first_frame := animator.frame
	await wait_seconds(0.25)
	assert_ne(animator.frame, first_frame, "walk animation must visibly advance")
	var sheet := RaptorSheet.get_image()
	var hashes: Dictionary = {}
	for row: int in AnimatorScript.WALK_ROWS:
		var region := sheet.get_region(Rect2i(
			AnimatorScript.Direction.E * 96, row * 80, 96, 80))
		hashes[hash(region.get_data())] = true
	assert_gte(hashes.size(), 3, "four walk rows need visibly different leg poses")


func test_north_is_rear_and_south_exposes_pale_chest() -> void:
	var sheet := RaptorSheet.get_image()
	var north_pale := _count_pale_pixels(sheet, AnimatorScript.Direction.N, 0)
	var south_pale := _count_pale_pixels(sheet, AnimatorScript.Direction.S, 0)
	assert_gt(south_pale, north_pale + 20)


func test_sheet_frames_are_nonempty_and_have_no_magenta_key_pixels() -> void:
	var sheet := RaptorSheet.get_image()
	for row: int in range(6):
		for column: int in range(8):
			var opaque_pixels := 0
			for y: int in range(80):
				for x: int in range(96):
					var color := sheet.get_pixel(column * 96 + x, row * 80 + y)
					if color.a <= 0.01:
						continue
					opaque_pixels += 1
					var is_magenta_key := color.r > 0.65 and color.b > 0.55 \
							and color.g < minf(color.r, color.b) * 0.55
					assert_false(is_magenta_key,
							"magenta key pixel remains at %d,%d" % [
								column * 96 + x, row * 80 + y])
			assert_gt(opaque_pixels, 250,
					"direction %d row %d must contain a full raptor pose" % [
						column, row])


func test_default_data_keeps_chase_fast_but_slows_patrol() -> void:
	var data: CreatureData = load("res://data/creatures/raptor.tres")
	assert_eq(data.walk_speed, 55.0)
	assert_eq(data.chase_speed, 200.0)


func test_noise_telegraph_faces_sound_before_showing_walk() -> void:
	var animator := AnimatorScript.new() as RaptorSpriteAnimator
	add_child_autofree(animator)
	await wait_physics_frames(1)

	animator.begin_sense_telegraph(&"noise", Vector2.LEFT)
	animator.update_from_velocity(Vector2.RIGHT, Raptor.State.INVESTIGATE)
	assert_eq(animator.animation, &"idle_W", "소리 방향을 향한 idle이 이동 표현보다 먼저 보여야 한다")

	animator.end_sense_telegraph()
	animator.update_from_velocity(Vector2.RIGHT, Raptor.State.INVESTIGATE)
	assert_eq(animator.animation, &"walk_E")


func test_main_scene_raptors_have_sprite_animators() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(1)
	var raptor: Raptor = main.get_node("Raptor") as Raptor
	assert_not_null(raptor.get_node_or_null("SpriteAnimator"))


func _count_pale_pixels(sheet: Image, column: int, row: int) -> int:
	var count := 0
	for y: int in range(80):
		for x: int in range(96):
			var color := sheet.get_pixel(column * 96 + x, row * 80 + y)
			if color.a > 0.2 and color.r > 0.28 and color.g > 0.28 \
					and color.b < color.g * 0.9:
				count += 1
	return count

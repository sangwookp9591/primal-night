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
	assert_eq(RaptorSheet.get_size(), Vector2(512.0, 384.0))
	assert_eq(animator.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(animator.offset, Vector2(0.0, -32.0))
	assert_eq(animator.sprite_frames.get_frame_texture(&"idle_S", 0).get_size(), Vector2(64.0, 64.0))
	assert_eq(animator.animation, &"idle_S")


func test_raptor_visual_updates_for_walk_chase_and_idle_last_direction() -> void:
	var animator: AnimatedSprite2D = AnimatorScript.new()
	add_child_autofree(animator)
	await wait_physics_frames(1)

	animator.update_from_velocity(Vector2.RIGHT, Raptor.State.WANDER)
	assert_eq(animator.animation, &"walk_E")
	assert_eq(animator.speed_scale, 1.0)

	animator.update_from_velocity(Vector2.RIGHT, Raptor.State.CHASE)
	assert_eq(animator.animation, &"walk_E")
	assert_almost_eq(animator.speed_scale, AnimatorScript.CHASE_SPEED_SCALE, 0.001)

	animator.update_from_velocity(Vector2.ZERO, Raptor.State.CHASE)
	assert_eq(animator.animation, &"idle_E")
	assert_eq(animator.speed_scale, 1.0)


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

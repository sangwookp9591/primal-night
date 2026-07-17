extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const AnimatorScript = preload("res://scripts/player/player_sprite_animator.gd")
const SheetTexture: Texture2D = preload("res://assets/sprites/player/player_survivor_sheet.png")


func test_direction_for_vector_uses_eight_45_degree_sectors() -> void:
	var cases: Array[Dictionary] = [
		{ vector = Vector2.UP, direction = PlayerSpriteAnimator.Direction.N },
		{ vector = Vector2(1.0, -1.0), direction = PlayerSpriteAnimator.Direction.NE },
		{ vector = Vector2.RIGHT, direction = PlayerSpriteAnimator.Direction.E },
		{ vector = Vector2(1.0, 1.0), direction = PlayerSpriteAnimator.Direction.SE },
		{ vector = Vector2.DOWN, direction = PlayerSpriteAnimator.Direction.S },
		{ vector = Vector2(-1.0, 1.0), direction = PlayerSpriteAnimator.Direction.SW },
		{ vector = Vector2.LEFT, direction = PlayerSpriteAnimator.Direction.W },
		{ vector = Vector2(-1.0, -1.0), direction = PlayerSpriteAnimator.Direction.NW },
	]
	for item: Dictionary in cases:
		assert_eq(PlayerSpriteAnimator.direction_for_vector(item.vector), item.direction)


func test_sprite_frames_contain_all_directional_idle_and_walk_animations() -> void:
	var frames: SpriteFrames = PlayerSpriteAnimator.build_sprite_frames()
	for direction: int in range(PlayerSpriteAnimator.DIRECTION_COUNT):
		var idle: StringName = PlayerSpriteAnimator.animation_name(false, direction)
		var walk: StringName = PlayerSpriteAnimator.animation_name(true, direction)
		assert_true(frames.has_animation(idle), "missing %s" % idle)
		assert_true(frames.has_animation(walk), "missing %s" % walk)
		assert_eq(frames.get_frame_count(idle), 2)
		assert_eq(frames.get_frame_count(walk), 4)


func test_real_player_scene_loads_runtime_sheet_and_uses_foot_anchor() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	await wait_physics_frames(1)
	var animator: PlayerSpriteAnimator = player.get_node("VisualRig/BaseBody") as PlayerSpriteAnimator
	var body: ColorRect = player.get_node("Body") as ColorRect

	assert_not_null(animator)
	assert_false(body.visible, "gray-box ColorRect remains only as a hidden compatibility node")
	assert_eq(SheetTexture.get_size(), Vector2(384.0, 384.0))
	assert_eq(animator.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(animator.offset, Vector2(0.0, -32.0), "48x64 cell origin is the bottom-center foot contact")
	assert_eq(animator.sprite_frames.get_frame_texture(&"idle_S", 0).get_size(), Vector2(48.0, 64.0))
	assert_eq(animator.animation, &"idle_S")


func test_player_velocity_updates_walk_animation_speed_and_idle_last_direction() -> void:
	var animator: PlayerSpriteAnimator = AnimatorScript.new()
	add_child_autofree(animator)
	await wait_physics_frames(1)

	animator.update_from_velocity(Vector2.RIGHT, Player.Stance.WALK)
	assert_eq(animator.animation, &"walk_E")
	assert_eq(animator.speed_scale, 1.0)

	animator.update_from_velocity(Vector2.RIGHT, Player.Stance.RUN)
	assert_eq(animator.animation, &"walk_E")
	assert_eq(animator.speed_scale, 1.5)

	animator.update_from_velocity(Vector2.LEFT, Player.Stance.CROUCH)
	assert_eq(animator.animation, &"walk_W")
	assert_almost_eq(animator.speed_scale, 0.6, 0.001)

	animator.update_from_velocity(Vector2.ZERO, Player.Stance.WALK)
	assert_eq(animator.animation, &"idle_W", "idle keeps the last moving direction")
	assert_eq(animator.speed_scale, 1.0)

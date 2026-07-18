extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func test_bleeding_movement_leaves_fading_visual_only_drop() -> void:
	var player := PlayerScene.instantiate() as Player
	add_child_autofree(player)
	await wait_physics_frames(1)
	var trail := player.get_node("BloodTrail") as BloodTrail
	player.health.start_bleeding()
	player.velocity = Vector2.RIGHT * 50.0
	player.global_position = Vector2(40.0, 20.0)
	trail._process(BloodTrail.DROP_INTERVAL_SECONDS + 0.01)

	assert_eq(trail.drops.size(), 1)
	assert_eq(trail.drops[0].position, Vector2(40.0, 20.0))
	trail._process(BloodTrail.DROP_LIFETIME_SECONDS + 0.01)
	assert_eq(trail.drops.size(), 0, "핏자국은 시간이 지나면 사라진다")

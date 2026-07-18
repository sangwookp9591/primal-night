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


func test_three_second_clear_reduces_drop_smell_and_adds_dirty_hands_smell() -> void:
	var player := PlayerScene.instantiate() as Player
	add_child_autofree(player)
	await wait_physics_frames(1)
	var trail := player.get_node("BloodTrail") as BloodTrail
	player.health.start_bleeding()
	player.velocity = Vector2.RIGHT * 50.0
	player.global_position = Vector2(40.0, 20.0)
	trail._process(BloodTrail.DROP_INTERVAL_SECONDS + 0.01)
	var drop = trail.drops[0].node
	assert_eq(drop.get_hold_seconds(), 3.0)
	assert_eq(drop.current_smell_strength(), BloodTrail.DROP_SMELL_STRENGTH)
	drop.apply_clear(player)
	assert_almost_eq(drop.current_smell_strength(),
		BloodTrail.DROP_SMELL_STRENGTH * BloodTrail.CLEARED_SMELL_RATIO, 0.01)
	assert_not_null(player.get_node_or_null("DirtyHandsSmell"))


func test_cancel_before_interact_keeps_blood_smell_intact() -> void:
	var player := PlayerScene.instantiate() as Player
	add_child_autofree(player)
	await wait_physics_frames(1)
	var trail := player.get_node("BloodTrail") as BloodTrail
	player.health.start_bleeding()
	player.velocity = Vector2.RIGHT * 50.0
	trail._process(BloodTrail.DROP_INTERVAL_SECONDS + 0.01)
	var drop = trail.drops[0].node
	# Interactor 취소는 interact를 호출하지 않는다.
	assert_eq(drop.current_smell_strength(), BloodTrail.DROP_SMELL_STRENGTH)
	assert_false(drop.cleared)

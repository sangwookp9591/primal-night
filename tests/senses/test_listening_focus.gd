extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func before_each() -> void:
	Input.action_release("cycle_target")


func after_each() -> void:
	Input.action_release("cycle_target")


func test_stationary_hold_emits_direction_only_hint_and_locks_movement() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	await wait_physics_frames(1)
	watch_signals(player)
	get_node("/root/EventBus").noise_emitted.emit(
		player.global_position + Vector2(80.0, -40.0), 200.0, null)
	Input.action_press("cycle_target")
	player._physics_process(Player.LISTEN_HOLD_SECONDS + 0.01)

	assert_signal_emitted(player, "listening_hint")
	var params: Array = get_signal_parameters(player, "listening_hint", 0)
	assert_almost_eq((params[0] as Vector2).length(), 1.0, 0.001,
		"힌트 페이로드는 거리 없이 정규화 방향만 제공한다")
	assert_true(player.movement_locked, "듣는 동안 완전히 정지한다")

	Input.action_release("cycle_target")
	player._physics_process(0.01)
	assert_false(player.movement_locked)

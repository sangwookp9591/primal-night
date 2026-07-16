extends GutTest

## Player 통합: 스태미나가 T1 의 달리기 속도에 실제로 영향을 주는가.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

func before_each() -> void:
	Input.action_release("move_right")
	Input.action_release("run")

func after_each() -> void:
	Input.action_release("move_right")
	Input.action_release("run")

func test_player_has_survival_components() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	assert_not_null(player.health, "Player 에 HealthComponent 가 붙어 있어야 한다")
	assert_not_null(player.stamina, "Player 에 StaminaComponent 가 붙어 있어야 한다")
	assert_not_null(player.injury, "Player 에 InjuryComponent 가 붙어 있어야 한다")

func test_running_drains_stamina() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var before: float = player.stamina.current_stamina

	Input.action_press("move_right")
	Input.action_press("run")
	await wait_physics_frames(10)

	assert_lt(player.stamina.current_stamina, before, "달리면 스태미나가 줄어야 한다")

func test_walking_does_not_drain_stamina() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.stamina.current_stamina = 50.0

	Input.action_press("move_right")
	await wait_physics_frames(10)

	assert_gt(player.stamina.current_stamina, 50.0, "걸으면 스태미나가 회복되어야 한다")

## ★ 완료판정 2번: 스태미나 0 에서 달리기가 불가능하다.
func test_exhausted_player_moves_at_walk_speed_even_while_holding_run() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	# 먼저 달리기 속도가 실제로 나오는지 확인한다 (그래야 아래 비교가 의미가 있다).
	Input.action_press("move_right")
	Input.action_press("run")
	await wait_physics_frames(2)
	assert_almost_eq(player.velocity.length(), player.config.run_speed, 0.5, "스태미나가 있으면 달리기 속도가 나와야 한다")

	# 스태미나를 소진시킨다.
	player.stamina.current_stamina = 0.0
	player.stamina.is_exhausted = true
	await wait_physics_frames(1)

	assert_almost_eq(player.velocity.length(), player.config.walk_speed, 0.5,
		"스태미나 0 이면 run 을 누르고 있어도 걷기 속도여야 한다")
	assert_lt(player.config.walk_speed, player.config.run_speed, "걷기가 달리기보다 느려야 비교가 성립한다")

## 달리기 소음 반경도 걷기 값으로 떨어져야 한다 (T1 의 get_noise_radius 계약을 깨지 않는다).
func test_exhausted_player_emits_walk_noise_not_run_noise() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.stamina.current_stamina = 0.0
	player.stamina.is_exhausted = true

	Input.action_press("move_right")
	Input.action_press("run")
	await wait_physics_frames(1)

	assert_eq(player.get_noise_radius(), player.config.walk_noise_profile.radius,
		"달리지 못하면 달리기 소음이 아니라 걷기 소음이 나야 한다")

## 치료 중에는 이동이 제한된다 (설계서 5.2).
func test_movement_lock_stops_the_player() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	player.movement_locked = true
	Input.action_press("move_right")
	await wait_physics_frames(5)

	assert_eq(player.velocity, Vector2.ZERO, "이동이 잠기면 속도가 0 이어야 한다")
	assert_eq(player.get_noise_radius(), 0.0, "이동이 잠기면 소음도 나지 않아야 한다")

func test_leg_laceration_reduces_actual_movement_speed() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.injury.apply_host_leg_laceration(0.0)

	Input.action_press("move_right")
	await wait_physics_frames(2)

	assert_almost_eq(player.velocity.length(),
		player.config.walk_speed * player.health.config.leg_laceration_move_multiplier, 0.5,
		"다리 열상 이동 배율이 실제 이동 속도에 적용되어야 한다")

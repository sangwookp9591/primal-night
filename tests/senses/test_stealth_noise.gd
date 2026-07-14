extends GutTest

## 은신 최소 구현 (W4-T1, 설계서 5.6): 웅크리기 속도/소음 감소, 수풀 소음 변화.
## StealthZone(수풀)과 Player 크라우치 상태가 실제 소음 반경·프로필에 반영되는지 검증한다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const StealthZoneScript = preload("res://scripts/world/stealth_zone.gd")
const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")
	Input.action_release("move_right")
	Input.action_release("run")
	Input.action_release("crouch")

func after_each() -> void:
	Input.action_release("move_right")
	Input.action_release("run")
	Input.action_release("crouch")

func _make_bush(at: Vector2, size: Vector2) -> StealthZone:
	var zone: StealthZone = StealthZoneScript.new()
	zone.collision_layer = 0
	zone.collision_mask = 2
	zone.position = at
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	zone.add_child(shape)
	add_child_autofree(zone)
	return zone

func _make_raptor_data() -> CreatureData:
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 10.0
	data.lose_sight_radius = 20.0
	data.smell_threshold = 999.0
	data.ai_tick_interval = 0.2
	data.occlusion_attenuation = 1.0
	return data

func test_crouch_reduces_move_speed() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	Input.action_press("move_right")
	Input.action_press("crouch")
	await wait_physics_frames(2)

	assert_almost_eq(player.velocity.length(), player.config.crouch_speed, 0.5,
		"웅크리면 웅크리기 속도로 움직여야 한다")
	assert_lt(player.config.crouch_speed, player.config.walk_speed,
		"웅크리기가 걷기보다 느려야 비교가 성립한다")

func test_crouching_overrides_the_run_input() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	Input.action_press("move_right")
	Input.action_press("run")
	Input.action_press("crouch")
	await wait_physics_frames(2)

	assert_almost_eq(player.velocity.length(), player.config.crouch_speed, 0.5,
		"run 을 같이 눌러도 웅크리면 은신이 우선한다")

func test_crouch_reduces_noise_radius() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	Input.action_press("move_right")
	Input.action_press("crouch")
	await wait_physics_frames(1)

	assert_eq(player.get_noise_radius(), player.config.crouch_noise_profile.radius,
		"웅크리면 웅크리기 소음 반경이 나와야 한다")
	assert_lt(player.config.crouch_noise_profile.radius, player.config.walk_noise_profile.radius,
		"웅크리기 소음이 걷기보다 작아야 비교가 성립한다")

func test_stealth_zone_marks_the_player_in_bush_on_enter_and_clears_on_exit() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.position = Vector2(-500.0, -500.0)
	var bush: StealthZone = _make_bush(Vector2.ZERO, Vector2(200.0, 200.0))
	await wait_physics_frames(1)
	assert_false(player.in_bush, "수풀 밖에서는 in_bush 가 꺼져 있어야 한다")

	player.position = Vector2.ZERO
	await wait_physics_frames(2)
	assert_true(player.in_bush, "수풀에 들어가면 in_bush 가 켜져야 한다")

	player.position = Vector2(-500.0, -500.0)
	await wait_physics_frames(2)
	assert_false(player.in_bush, "수풀을 나가면 in_bush 가 꺼져야 한다")

func test_running_through_bush_increases_the_noise_radius() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	_make_bush(Vector2.ZERO, Vector2(400.0, 400.0))
	player.position = Vector2.ZERO
	await wait_physics_frames(2)
	assert_true(player.in_bush, "전제: 플레이어가 수풀 안에 있어야 한다")

	Input.action_press("move_right")
	Input.action_press("run")
	await wait_physics_frames(1)

	assert_eq(player.get_noise_radius(), player.config.bush_run_noise_profile.radius,
		"수풀에서 달리면 수풀 통과 소음 반경이 나와야 한다")
	assert_gt(player.config.bush_run_noise_profile.radius, player.config.run_noise_profile.radius,
		"수풀 달리기 소음이 평소 달리기보다 커야 비교가 성립한다")

func test_crouching_in_bush_stays_quiet_not_the_bush_run_profile() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	_make_bush(Vector2.ZERO, Vector2(400.0, 400.0))
	player.position = Vector2.ZERO
	await wait_physics_frames(2)

	Input.action_press("move_right")
	Input.action_press("crouch")
	await wait_physics_frames(1)

	assert_eq(player.get_noise_radius(), player.config.crouch_noise_profile.radius,
		"수풀 안이라도 웅크리면 조용한 소음 반경을 유지해야 한다")

## ★ 완료판정: 같은 거리에서도 웅크림/달리기에 따라 랩터의 반응이 갈려야 한다
## (테스트 전략의 "랩터 조사 전환 차이"). 실제 발신 경로(NoiseEmitter → EventBus)를 그대로 쓴다.
func test_raptor_investigates_a_running_player_but_not_a_crouching_one_at_the_same_distance() -> void:
	var raptor: Raptor = RaptorScript.new()
	raptor.data = _make_raptor_data()
	raptor.position = Vector2.ZERO
	add_child_autofree(raptor)

	var player: Player = add_child_autofree(PlayerScene.instantiate())
	# 웅크리기 반경(30) 밖, 걷기 반경(80)과 달리기 반경(160) 안인 거리 —
	# 웅크리기가 "안 들림"으로 걷기와 구분되는지까지 검증한다.
	var distance: Vector2 = Vector2(50.0, 0.0)
	player.position = distance

	# 실제 발신 주기(noise_emit_interval)만큼 한 번에 흘려보내 실제 발신 경로를 그대로 탄다.
	Input.action_press("move_right")
	Input.action_press("crouch")
	player._physics_process(player.config.noise_emit_interval)
	await wait_physics_frames(1)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER,
		"웅크린 발소리는 이 거리에서 들리지 않아야 한다")

	Input.action_release("crouch")
	Input.action_press("run")
	player.position = distance
	player._physics_process(player.config.noise_emit_interval)
	await wait_physics_frames(1)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE,
		"같은 거리라도 달리면 랩터가 알아채야 한다")

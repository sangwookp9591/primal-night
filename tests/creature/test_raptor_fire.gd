extends GutTest

## 랩터의 불 회피 (설계서 5.5: 랩터는 불을 회피한다).
## - 등록된 모닥불 반경 안으로는 들어오지 않는다.
## - 추격 중이라도 플레이어가 불 반경에 들어가면 추격을 포기하고 물러난다.
## - 반경 경계에서 상태가 진동하지 않도록 히스테리시스를 둔다.

const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")

const FIRE_POSITION: Vector2 = Vector2(400.0, 0.0)
const FIRE_RADIUS: float = 200.0

var _event_bus: Node = null
var _campfire_registry: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")
	_campfire_registry = get_node("/root/CampfireRegistry")
	_campfire_registry.clear_for_test()

func _make_data() -> CreatureData:
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 400.0
	data.lose_sight_radius = 600.0
	data.investigate_arrive_distance = 24.0
	data.fire_exit_ratio = 1.3
	return data

func _spawn_raptor(data: CreatureData, at: Vector2) -> Raptor:
	var raptor: Raptor = RaptorScript.new()
	raptor.data = data
	raptor.position = at
	add_child_autofree(raptor)
	return raptor

func _spawn_player(at: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	player.position = at
	add_child_autofree(player)
	return player

func _light_fire() -> Node2D:
	var campfire: Node2D = add_child_autofree(Node2D.new())
	campfire.position = FIRE_POSITION
	_campfire_registry.register_fire(campfire, FIRE_POSITION, FIRE_RADIUS)
	return campfire

func test_chase_is_abandoned_when_player_reaches_the_fire() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var player: Node2D = _spawn_player(Vector2(100.0, 0.0))
	_light_fire()
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.CHASE, "전제: 불 밖 플레이어를 추격 중이다")

	# 플레이어가 모닥불 곁으로 도망친다 — 목표 장면의 결말.
	player.position = FIRE_POSITION + Vector2(-50.0, 0.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.FLEE, "플레이어가 불 반경에 들어가면 추격을 포기한다")

func test_flee_target_moves_away_from_the_fire() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2(250.0, 0.0))
	var player: Node2D = _spawn_player(Vector2(300.0, 0.0))
	_light_fire()
	raptor._ai_tick()
	player.position = FIRE_POSITION
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.FLEE, "전제: 도주 상태여야 한다")

	var target_distance: float = raptor.move_target.distance_to(FIRE_POSITION)
	var current_distance: float = raptor.global_position.distance_to(FIRE_POSITION)
	assert_gt(target_distance, current_distance, "도주 목표는 불에서 멀어지는 방향이다")
	assert_gt(target_distance, FIRE_RADIUS * raptor.data.fire_exit_ratio - 1.0,
		"도주 목표는 히스테리시스 반경 밖이다")

func test_raptor_caught_inside_a_new_fire_radius_retreats() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), FIRE_POSITION + Vector2(100.0, 0.0))
	_light_fire()

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.FLEE, "불 반경 안에 있으면 물러난다")


func test_raptor_spawned_after_fire_reads_existing_registry_state() -> void:
	_light_fire()
	var raptor: Raptor = _spawn_raptor(
		_make_data(), FIRE_POSITION + Vector2(100.0, 0.0))

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.FLEE,
		"늦게 스폰된 랩터도 이미 켜진 불을 즉시 피해야 한다")


func test_no_state_oscillation_at_the_fire_boundary() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2(150.0, 0.0))
	var player: Node2D = _spawn_player(Vector2(200.0, 0.0))
	_light_fire()
	raptor._ai_tick()
	player.position = FIRE_POSITION
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.FLEE, "전제: 도주 상태여야 한다")

	# 반경(200)과 이탈 반경(260) 사이 경계 지대에 서 있다.
	# 플레이어가 여전히 시야 안(불 안)이어도 추격으로 되돌아가면 안 된다.
	raptor.global_position = FIRE_POSITION + Vector2(-230.0, 0.0)
	watch_signals(raptor)
	for tick_index: int in range(5):
		raptor._ai_tick()
		assert_eq(raptor.state, Raptor.State.FLEE,
			"경계 지대에서는 도주가 유지된다 (틱 %d, 진동 금지)" % tick_index)
	assert_signal_emit_count(raptor, "state_changed", 0, "경계 지대에서 상태 전환이 없어야 한다")

func test_flee_ends_outside_the_exit_radius() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2(150.0, 0.0))
	var player: Node2D = _spawn_player(Vector2(200.0, 0.0))
	_light_fire()
	raptor._ai_tick()
	player.position = FIRE_POSITION
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.FLEE, "전제: 도주 상태여야 한다")

	# 이탈 반경(260) 밖까지 물러났다. 플레이어는 여전히 불 안 → 추격 재진입도 금지.
	raptor.global_position = FIRE_POSITION + Vector2(-300.0, 0.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "이탈 반경 밖에서는 배회로 복귀한다")

	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.WANDER,
		"플레이어가 불 안에 있는 동안에는 추격에 다시 들어가지 않는다")

func test_extinguished_fire_no_longer_protects_the_player() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2(150.0, 0.0))
	var player: Node2D = _spawn_player(FIRE_POSITION)
	var campfire: Node2D = _light_fire()
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.FLEE, "전제: 불이 살아 있으면 접근하지 않는다")
	raptor.global_position = FIRE_POSITION + Vector2(-300.0, 0.0)
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.WANDER, "전제: 배회로 복귀했다")

	_campfire_registry.unregister_fire(campfire)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.CHASE, "불이 꺼지면 더 이상 보호받지 못한다")

func test_investigation_target_is_clamped_outside_fire_radius() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	_light_fire()

	# 불 한가운데서 소리가 났다 — 조사하되 반경 안으로는 들어가지 않는다.
	_event_bus.noise_emitted.emit(FIRE_POSITION, 800.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "불 안의 소리도 조사는 한다")
	assert_gt(raptor.move_target.distance_to(FIRE_POSITION), FIRE_RADIUS - 1.0,
		"조사 목표는 불 반경 밖으로 클램프된다 (반경 안으로 들어오지 않는다)")

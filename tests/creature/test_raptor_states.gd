extends GutTest

## 랩터 상태기계 (설계서 5.5): 배회 → 조사 → 추격, 대상 상실 처리.
## - 냄새는 좌표가 아니라 농도 경사를 따라 거슬러 올라간다 (설계서 5.4).
## - 추격은 플레이어를 실제로 지각한 경우에만 진입한다.
## - 추격 전환 시 인지 가능한 신호를 낸다 (설계서 3.2: 예고 없는 위협 금지).

const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _make_data() -> CreatureData:
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 100.0
	data.lose_sight_radius = 200.0
	data.smell_threshold = 8.0
	data.investigate_arrive_distance = 24.0
	data.occlusion_attenuation = 0.5
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

func _spawn_smell_grid() -> SmellGrid:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2(-500.0, -500.0)
	grid.area_size = Vector2(1000.0, 1000.0)
	add_child_autofree(grid)
	return grid

func test_smell_above_threshold_triggers_investigation_along_gradient() -> void:
	var grid: SmellGrid = _spawn_smell_grid()
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2(50.0, 50.0))
	await wait_physics_frames(1)
	# 랩터 셀(0..100)에 문턱 이상, 동쪽 셀(100..200)에 더 진한 냄새.
	_event_bus.smell_emitted.emit(Vector2(50.0, 50.0), 10.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(150.0, 50.0), 100.0, &"blood")

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "문턱 이상 냄새는 조사를 촉발한다")
	assert_gt(raptor.move_target.x, raptor.global_position.x,
		"정확한 발생 좌표가 아니라 농도가 진해지는 방향으로 이동한다")

func test_smell_below_threshold_is_ignored() -> void:
	var grid: SmellGrid = _spawn_smell_grid()
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2(50.0, 50.0))
	await wait_physics_frames(1)
	_event_bus.smell_emitted.emit(Vector2(50.0, 50.0), 2.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(150.0, 50.0), 5.0, &"blood")

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "약한 냄새는 무시한다")

func test_arriving_at_investigation_spot_with_nothing_returns_to_wander() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var noise_position: Vector2 = Vector2(300.0, 0.0)
	_event_bus.noise_emitted.emit(noise_position, 500.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "전제: 조사 상태여야 한다")

	# 조사 지점에 도착했지만 아무것도 없다.
	raptor.global_position = noise_position + Vector2(10.0, 0.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "조사 지점에 아무것도 없으면 배회로 복귀한다 (대상 상실)")

func test_seeing_player_triggers_chase_with_perceivable_alert() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var player: Node2D = _spawn_player(Vector2(80.0, 0.0))
	watch_signals(raptor)

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.CHASE, "시야 안 플레이어는 추격을 촉발한다")
	assert_signal_emitted(raptor, "chase_started",
		"추격 전환은 인지 가능한 신호를 낸다 (설계서 3.2)")

func test_player_outside_sight_radius_is_not_perceived() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	_spawn_player(Vector2(150.0, 0.0))

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "시야 밖 플레이어는 지각되지 않는다")

func test_chase_tracks_player_while_perceived() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var player: Node2D = _spawn_player(Vector2(80.0, 0.0))
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.CHASE, "전제: 추격 상태여야 한다")

	player.position = Vector2(120.0, 40.0)
	raptor._ai_tick()

	assert_eq(raptor.move_target, Vector2(120.0, 40.0), "지각이 유지되는 동안에는 목표를 갱신한다")

func test_losing_sight_downgrades_to_investigating_last_seen_position() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var player: Node2D = _spawn_player(Vector2(80.0, 0.0))
	raptor._ai_tick()
	var last_seen: Vector2 = Vector2(150.0, 0.0)
	player.position = last_seen
	raptor._ai_tick()

	# lose_sight_radius(200) 밖으로 벗어난다.
	player.position = Vector2(500.0, 0.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "시야를 잃으면 조사로 강등된다")
	assert_eq(raptor.move_target, last_seen, "마지막 목격 위치를 조사한다 (실시간 좌표 추적 금지)")

func test_sight_hysteresis_keeps_chase_between_radii() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var player: Node2D = _spawn_player(Vector2(80.0, 0.0))
	raptor._ai_tick()

	# sight_radius(100) 밖이지만 lose_sight_radius(200) 안 — 추격 유지.
	player.position = Vector2(150.0, 0.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.CHASE, "이탈 반경 전까지는 추격을 유지한다 (히스테리시스)")

extends GutTest

## 냄새 격자 (설계서 5.4 / 성능문서 5.2).
## 핵심 계약: EventBus.smell_emitted 를 받아 셀에 쌓고,
## 바람 방향으로 이동(advect)하며 시간에 따라 감소(decay)한다.
## 갱신은 매 프레임이 아니라 tick_interval 주기로만 일어난다.

const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _make_config() -> SmellGridConfig:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	config.tick_interval = 0.25
	config.decay_factor = 0.8
	config.advect_fraction = 0.5
	config.min_active_value = 0.5
	return config

func _make_grid(config: SmellGridConfig) -> SmellGrid:
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2(0.0, 0.0)
	grid.area_size = Vector2(1000.0, 1000.0)
	grid.wind_direction = Vector2.ZERO
	grid.wind_strength = 1.0
	add_child_autofree(grid)
	return grid

func _make_client_grid(config: SmellGridConfig) -> SmellGrid:
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2(0.0, 0.0)
	grid.area_size = Vector2(1000.0, 1000.0)
	grid.set_multiplayer_authority(2)
	add_child_autofree(grid)
	return grid

## 셀 중심 좌표 (셀 인덱스 → 월드 좌표). 경계 반올림 문제를 피한다.
func _cell_center(grid: SmellGrid, cell_x: int, cell_y: int) -> Vector2:
	var size: float = grid.config.cell_size
	return grid.area_origin + Vector2((float(cell_x) + 0.5) * size, (float(cell_y) + 0.5) * size)

func test_smell_emitted_deposits_at_position() -> void:
	var grid: SmellGrid = _make_grid(_make_config())
	var spot: Vector2 = _cell_center(grid, 2, 2)

	_event_bus.smell_emitted.emit(spot, 60.0, &"blood")

	assert_eq(grid.get_smell_at(spot), 60.0, "발신 즉시 해당 셀에 냄새가 쌓여야 한다")
	assert_eq(grid.get_active_cell_count(), 1, "활성 셀 목록으로 관리해야 한다 (성능문서 5.2)")

func test_client_peer_does_not_simulate_smell_grid() -> void:
	var grid: SmellGrid = _make_client_grid(_make_config())
	var spot: Vector2 = _cell_center(grid, 2, 2)

	_event_bus.smell_emitted.emit(spot, 60.0, &"blood")
	grid._process(grid.config.tick_interval)

	assert_eq(grid.get_smell_at(spot), 0.0,
		"클라이언트 냄새 격자는 자체 이벤트/감쇠 시뮬레이션을 실행하지 않는다")
	assert_eq(grid.get_active_cell_count(), 0, "디버그 표시는 호스트 복제 데이터만 그려야 한다")

func test_client_smell_grid_applies_authority_debug_snapshot() -> void:
	var grid: SmellGrid = _make_client_grid(_make_config())
	var spot: Vector2 = _cell_center(grid, 2, 2)
	var index: int = grid.get_cell_index_for_debug(spot)

	grid.apply_smell_snapshot(PackedInt32Array([index]), PackedFloat32Array([42.0]))

	assert_eq(grid.get_smell_at(spot), 42.0, "클라이언트 디버그 격자는 호스트 스냅샷 값만 그린다")
	assert_eq(grid.get_active_cell_count(), 1, "복제된 활성 셀만 디버그 대상으로 남는다")

func test_repeated_smell_accumulates_in_the_same_cell() -> void:
	var grid: SmellGrid = _make_grid(_make_config())
	var spot: Vector2 = _cell_center(grid, 2, 2)

	_event_bus.smell_emitted.emit(spot, 60.0, &"blood")
	_event_bus.smell_emitted.emit(spot + Vector2(10.0, -10.0), 40.0, &"blood")

	assert_eq(grid.get_smell_at(spot), 100.0, "같은 셀의 냄새는 누적된다")
	assert_eq(grid.get_active_cell_count(), 1, "같은 셀이면 활성 셀은 하나다")

func test_no_decay_before_tick_interval_elapses() -> void:
	var grid: SmellGrid = _make_grid(_make_config())
	var spot: Vector2 = _cell_center(grid, 2, 2)
	_event_bus.smell_emitted.emit(spot, 60.0, &"blood")

	grid._process(0.1)
	grid._process(0.1)

	assert_eq(grid.get_smell_at(spot), 60.0, "틱 주기 전에는 갱신하지 않는다 (매 프레임 순회 금지)")

func test_smell_decays_each_tick() -> void:
	var config: SmellGridConfig = _make_config()
	var grid: SmellGrid = _make_grid(config)
	var spot: Vector2 = _cell_center(grid, 2, 2)
	_event_bus.smell_emitted.emit(spot, 60.0, &"blood")

	grid._process(config.tick_interval)

	assert_almost_eq(grid.get_smell_at(spot), 60.0 * config.decay_factor, 0.001,
		"틱마다 decay_factor 비율로 감소해야 한다")

func test_smell_fades_out_and_cell_deactivates() -> void:
	var config: SmellGridConfig = _make_config()
	var grid: SmellGrid = _make_grid(config)
	var spot: Vector2 = _cell_center(grid, 2, 2)
	_event_bus.smell_emitted.emit(spot, 60.0, &"blood")

	for tick_index: int in range(40):
		grid._process(config.tick_interval)

	assert_eq(grid.get_smell_at(spot), 0.0, "시간이 지나면 냄새가 완전히 사라진다")
	assert_eq(grid.get_active_cell_count(), 0, "약해진 셀은 비활성화된다 (활성 셀만 갱신)")

func test_wind_advects_smell_downwind() -> void:
	var config: SmellGridConfig = _make_config()
	var grid: SmellGrid = _make_grid(config)
	grid.wind_direction = Vector2.RIGHT
	grid.wind_strength = 1.0
	var origin_spot: Vector2 = _cell_center(grid, 2, 2)
	var downwind_spot: Vector2 = _cell_center(grid, 3, 2)
	var upwind_spot: Vector2 = _cell_center(grid, 1, 2)
	_event_bus.smell_emitted.emit(origin_spot, 100.0, &"blood")

	grid._process(config.tick_interval)

	assert_gt(grid.get_smell_at(downwind_spot), 0.0, "바람이 부는 쪽 셀로 냄새가 이동해야 한다")
	assert_lt(grid.get_smell_at(origin_spot), 100.0 * config.decay_factor + 0.001,
		"이동한 만큼 원점 셀은 줄어야 한다")
	assert_eq(grid.get_smell_at(upwind_spot), 0.0, "바람을 거스르는 쪽으로는 퍼지지 않는다")

## 바람이 어느 방향이든 실제 이류는 그 방향으로 일어나야 한다 (설계서 5.4).
## RIGHT 하나만 검증하면 wind offset 을 RIGHT 로 고정하는 결함이 통과한다 (T5 뮤테이션 M2).
## 케이스: [이름, 바람 벡터, 기대 셀 오프셋] — 4방향 + 대각선 4방향.
const WIND_DIRECTION_CASES: Array = [
	["동풍", Vector2.RIGHT, Vector2i(1, 0)],
	["서풍", Vector2.LEFT, Vector2i(-1, 0)],
	["북풍", Vector2.UP, Vector2i(0, -1)],
	["남풍", Vector2.DOWN, Vector2i(0, 1)],
	["남동풍", Vector2(1.0, 1.0), Vector2i(1, 1)],
	["남서풍", Vector2(-1.0, 1.0), Vector2i(-1, 1)],
	["북동풍", Vector2(1.0, -1.0), Vector2i(1, -1)],
	["북서풍", Vector2(-1.0, -1.0), Vector2i(-1, -1)],
]

func test_wind_advects_downwind_for_every_direction(
		params: Array = use_parameters(WIND_DIRECTION_CASES)) -> void:
	var direction_name: String = params[0]
	var wind: Vector2 = params[1]
	var offset: Vector2i = params[2]
	var config: SmellGridConfig = _make_config()
	var grid: SmellGrid = _make_grid(config)
	grid.wind_direction = wind
	grid.wind_strength = 1.0
	var origin_spot: Vector2 = _cell_center(grid, 4, 4)
	var downwind_spot: Vector2 = _cell_center(grid, 4 + offset.x, 4 + offset.y)
	var upwind_spot: Vector2 = _cell_center(grid, 4 - offset.x, 4 - offset.y)
	_event_bus.smell_emitted.emit(origin_spot, 100.0, &"blood")

	grid._process(config.tick_interval)

	assert_almost_eq(grid.get_smell_at(downwind_spot),
		100.0 * config.advect_fraction * config.decay_factor, 0.001,
		"%s: 바람이 부는 쪽 셀(오프셋 %s)로 이동분이 쌓여야 한다" % [direction_name, offset])
	assert_eq(grid.get_smell_at(upwind_spot), 0.0,
		"%s: 바람을 거스르는 쪽 셀로는 퍼지지 않는다" % direction_name)
	assert_almost_eq(grid.get_smell_at(origin_spot),
		100.0 * (1.0 - config.advect_fraction) * config.decay_factor, 0.001,
		"%s: 이동분만큼 원점 셀은 줄어야 한다" % direction_name)

func test_no_advection_when_wind_is_calm() -> void:
	var config: SmellGridConfig = _make_config()
	var grid: SmellGrid = _make_grid(config)
	grid.wind_direction = Vector2.RIGHT
	grid.wind_strength = 0.0
	var origin_spot: Vector2 = _cell_center(grid, 2, 2)
	var downwind_spot: Vector2 = _cell_center(grid, 3, 2)
	_event_bus.smell_emitted.emit(origin_spot, 100.0, &"blood")

	grid._process(config.tick_interval)

	assert_eq(grid.get_smell_at(downwind_spot), 0.0, "바람 세기 0이면 이동하지 않는다")

func test_gradient_points_toward_higher_concentration() -> void:
	var grid: SmellGrid = _make_grid(_make_config())
	var strong_spot: Vector2 = _cell_center(grid, 4, 2)
	var probe_spot: Vector2 = _cell_center(grid, 3, 2)
	_event_bus.smell_emitted.emit(strong_spot, 100.0, &"blood")
	_event_bus.smell_emitted.emit(probe_spot, 10.0, &"blood")

	var gradient: Vector2 = grid.get_gradient_direction(probe_spot)

	assert_gt(gradient.x, 0.0, "농도가 더 높은 동쪽을 가리켜야 한다 (경사 추적)")
	assert_almost_eq(gradient.y, 0.0, 0.001, "남북 농도 차가 없으면 y 성분은 0이다")

func test_gradient_is_zero_when_no_higher_neighbor() -> void:
	var grid: SmellGrid = _make_grid(_make_config())
	var peak_spot: Vector2 = _cell_center(grid, 2, 2)
	_event_bus.smell_emitted.emit(peak_spot, 100.0, &"blood")

	assert_eq(grid.get_gradient_direction(peak_spot), Vector2.ZERO,
		"자기 셀이 가장 진하면 경사는 없다 (냄새 원점 도달)")

func test_positions_outside_the_area_are_safe_and_zero() -> void:
	var grid: SmellGrid = _make_grid(_make_config())
	var outside: Vector2 = Vector2(-500.0, -500.0)

	_event_bus.smell_emitted.emit(outside, 60.0, &"blood")

	assert_eq(grid.get_smell_at(outside), 0.0, "영역 밖 발신은 무시한다 (크래시 금지)")
	assert_eq(grid.get_gradient_direction(outside), Vector2.ZERO, "영역 밖 경사는 0이다")
	assert_eq(grid.get_active_cell_count(), 0, "영역 밖 발신은 활성 셀을 만들지 않는다")

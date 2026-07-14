extends GutTest

## 디버그 시각화 (설계서 5.4 마지막 줄, 13장).
## 개발 빌드에서 토글로 켠다: 냄새 격자 농도, 바람, 랩터 상태·반경·목표, 소음 반경.
## 바람 방향/세기는 디버그 키로 바꿀 수 있어야 한다 (설계서 5.4).

const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")
const NoiseDebugScript = preload("res://scripts/senses/noise_debug.gd")
const RaptorScript = preload("res://scripts/creature/raptor.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _key(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event

func _make_grid() -> SmellGrid:
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = SmellGridConfigScript.new()
	add_child_autofree(grid)
	return grid

func test_f4_toggles_smell_grid_debug() -> void:
	var grid: SmellGrid = _make_grid()
	assert_false(grid.debug_enabled, "디버그 시각화는 기본으로 꺼져 있다")

	grid._unhandled_key_input(_key(KEY_F4))
	assert_true(grid.debug_enabled, "F4 로 켠다")

	grid._unhandled_key_input(_key(KEY_F4))
	assert_false(grid.debug_enabled, "F4 로 다시 끈다")

func test_f6_rotates_wind_direction() -> void:
	var grid: SmellGrid = _make_grid()
	grid.wind_direction = Vector2.RIGHT
	grid.wind_strength = 1.0

	grid._unhandled_key_input(_key(KEY_F6))

	assert_almost_eq(grid.wind_direction.angle(), TAU / 8.0, 0.001,
		"F6 은 바람 방향을 45도씩 돌린다")

func test_f7_cycles_wind_strength() -> void:
	var grid: SmellGrid = _make_grid()
	grid.wind_strength = 1.0

	grid._unhandled_key_input(_key(KEY_F7))
	assert_almost_eq(grid.wind_strength, 0.0, 0.001, "1.0 → 0.0")

	grid._unhandled_key_input(_key(KEY_F7))
	assert_almost_eq(grid.wind_strength, 0.5, 0.001, "0.0 → 0.5")

	grid._unhandled_key_input(_key(KEY_F7))
	assert_almost_eq(grid.wind_strength, 1.0, 0.001, "0.5 → 1.0")

func test_f4_toggles_raptor_debug() -> void:
	var raptor: Raptor = RaptorScript.new()
	add_child_autofree(raptor)
	assert_false(raptor.debug_enabled, "랩터 디버그도 기본으로 꺼져 있다")

	raptor._unhandled_key_input(_key(KEY_F4))

	assert_true(raptor.debug_enabled, "F4 로 랩터 상태·반경·목표 표시를 켠다")

func test_noise_markers_record_and_expire() -> void:
	var noise_debug: Node2D = NoiseDebugScript.new()
	add_child_autofree(noise_debug)
	noise_debug._unhandled_key_input(_key(KEY_F4))
	assert_true(noise_debug.debug_enabled, "전제: 디버그가 켜져 있다")

	_event_bus.noise_emitted.emit(Vector2(100.0, 0.0), 80.0, null)

	assert_eq(noise_debug.get_marker_count(), 1, "소음 반경 마커가 기록된다")

	noise_debug._process(1.0)

	assert_eq(noise_debug.get_marker_count(), 0, "마커는 잠시 뒤 만료된다")

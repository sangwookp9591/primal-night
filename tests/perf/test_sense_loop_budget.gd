extends GutTest

## W3~4 감지 루프 성능 회귀 게이트 (계획서 W4-T5, 성능문서 4.2/5.2/5.3/10).
##
## 이것은 저사양 PC 판정이 아니라 로컬 회귀 게이트다. 성능문서 10장대로 절대 예산은
## 최소사양 실측기에서만 판정하고, 여기서는 "구조가 무너졌는가"를 막는다:
##   - 냄새 격자가 활성 셀만 갱신하는가 (전체 격자 순회로 되돌아가지 않았는가)
##   - 반복 소리가 병합되는가 (매 프레임 이벤트 폭주로 되돌아가지 않았는가)
##   - 랩터 AI·냄새 틱에 계측 지점이 살아 있는가 (샘플이 사라지면 회귀를 볼 눈이 없다)
##   - 커밋된 기준선이 CPU 예산 안인가 (성능문서 4.2)
##
## 절대 시간(ms) 단정은 예산의 상한만 쓴다 — 개발기 실측은 그보다 한참 아래라
## 기기 편차로 깜빡이지 않는다. 회귀 폭(+10%/+20%) 판정은 기준선 문서가 맡는다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const NoiseProfileScript = preload("res://scripts/senses/noise_profile.gd")
const NoiseEmitterScript = preload("res://scripts/senses/noise_emitter.gd")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")

const BASELINE_JSON: String = "res://docs/technical/BASELINE_W3_4_SENSE_LOOP.json"

## 성능문서 4.2 CPU 예산 (p95 상한).
const AI_BUDGET_MS: float = 3.0
const SCENT_BUDGET_MS: float = 1.0
## 성능문서 4.1 프레임 예산 (p95 상한).
const FRAME_P95_BUDGET_MS: float = 20.0

## 냄새 활성 셀 상한. 회색 상자 한 판(출혈 1명 + 미끼 몇 개)에서 이보다 많아지면
## 감쇠·비활성화가 깨졌거나 원천이 새고 있다는 뜻이다 (성능문서 5.2: 활성 구역만 갱신).
const ACTIVE_CELL_CAP: int = 64

var _perf: Node = null
var _event_bus: Node = null


func before_each() -> void:
	_perf = get_node("/root/PerfMonitor")
	_event_bus = get_node("/root/EventBus")


## --- PerfMonitor: 회귀를 보려면 평균이 아니라 p95 가 필요하다 (성능문서 9장) ---

func test_perf_monitor_reports_p95_and_max_not_just_average() -> void:
	var key: StringName = &"test_percentile"
	# 1ms 를 18번, 10ms 를 2번. 20샘플의 p95 는 위에서 두 번째 값이므로 이 꼬리를 잡는다
	# (스파이크가 하나뿐이면 20샘플의 p95 가 그걸 빼는 것이 정의상 맞다 — 그래서 2개다).
	for index: int in range(20):
		_perf.begin_sample(key)
		_spin_usec(10000 if index >= 18 else 1000)
		_perf.end_sample(key)

	assert_eq(_perf.get_sample_count(key), 20, "샘플 수를 셀 수 있어야 한다")
	assert_gt(_perf.get_p95_ms(key), _perf.get_avg_ms(key) * 2.0,
		"p95 는 평균보다 꼬리를 크게 반영해야 한다 — 평균만 보면 스파이크를 놓친다")
	assert_gte(_perf.get_max_ms(key), _perf.get_p95_ms(key), "최대는 p95 이상이다")


func test_perf_monitor_returns_zero_for_unknown_key() -> void:
	assert_eq(_perf.get_p95_ms(&"nope"), 0.0, "없는 키는 0 이다 (계측 부재를 예산 통과로 읽지 않게)")
	assert_eq(_perf.get_sample_count(&"nope"), 0)


## --- 소리: 반복 발신 병합 (성능문서 5.3: 동일 위치의 반복 소리를 짧은 구간 내 병합) ---

func test_repeated_footsteps_at_one_spot_are_merged_into_few_events() -> void:
	var profile: NoiseProfile = NoiseProfileScript.new()
	profile.id = &"perf_walk"
	profile.radius = 120.0
	profile.merge_window_seconds = 0.25
	profile.merge_distance_px = 16.0
	var emitter: NoiseEmitter = NoiseEmitterScript.new()

	# ★ GDScript 람다는 지역 변수를 값으로 캡처한다 — int 로 세면 밖에서 0 으로 보인다.
	var tally: Dictionary = { count = 0 }
	var counter: Callable = func(_position: Vector2, _radius: float, _source: Node) -> void:
		tally.count += 1
	_event_bus.noise_emitted.connect(counter)

	# 1초 동안 매 물리 프레임(60회) 같은 자리에서 발소리를 낸다.
	var now: float = 0.0
	for _frame: int in range(60):
		now += 1.0 / 60.0
		emitter.emit_profile(_event_bus, profile, Vector2(100.0, 100.0), null, now, false)
	_event_bus.noise_emitted.disconnect(counter)
	var events: int = int(tally.count)

	# 병합 창 0.25초 → 1초에 4~5회면 충분하다. 60회가 나오면 랩터 AI 와 디버그 표시가
	# 불필요하게 흔들린다 (성능문서 5.3).
	assert_lte(events, 5, "같은 자리 반복 발소리는 병합된다 (관측 %d회)" % events)
	assert_gt(events, 0, "그렇다고 소리가 아예 사라지면 안 된다")


func test_moving_far_enough_breaks_the_merge_window() -> void:
	var profile: NoiseProfile = NoiseProfileScript.new()
	profile.id = &"perf_walk"
	profile.radius = 120.0
	profile.merge_window_seconds = 0.25
	profile.merge_distance_px = 16.0
	var emitter: NoiseEmitter = NoiseEmitterScript.new()

	assert_true(emitter.emit_profile(_event_bus, profile, Vector2.ZERO, null, 0.0, false),
		"첫 소리는 난다")
	assert_false(emitter.emit_profile(_event_bus, profile, Vector2(4.0, 0.0), null, 0.05, false),
		"창 안에서 제자리 소리는 병합된다")
	assert_true(emitter.emit_profile(_event_bus, profile, Vector2(400.0, 0.0), null, 0.10, false),
		"멀리 이동한 소리는 새 위치라 병합하지 않는다 — 병합이 소리를 삼키면 안 된다")


## --- 냄새: 활성 셀만 갱신 (성능문서 5.2) ---

func test_smell_grid_keeps_active_cells_bounded_and_reclaims_them() -> void:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 128.0
	config.tick_interval = 0.25
	config.decay_factor = 0.8
	config.min_active_value = 0.5
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2(-1280.0, -640.0)
	grid.area_size = Vector2(2560.0, 1280.0)
	add_child_autofree(grid)
	await wait_physics_frames(1)

	# 같은 자리에 계속 냄새를 부어도 활성 셀은 한 칸이다 — 셀 수는 원천 수가 아니라
	# 공간에 비례해야 한다.
	for _index: int in range(50):
		_event_bus.smell_emitted.emit(Vector2(64.0, 64.0), 60.0, &"blood")
	assert_eq(grid.get_active_cell_count(), 1, "한 셀에 50번 부어도 활성 셀은 1개다")

	# 여러 셀에 뿌린 뒤 발신을 끊으면 감쇠로 전부 회수된다 (누수 금지).
	for index: int in range(12):
		_event_bus.smell_emitted.emit(Vector2(200.0 * index, 100.0), 20.0, &"blood")
	assert_lte(grid.get_active_cell_count(), ACTIVE_CELL_CAP,
		"활성 셀이 상한을 넘으면 격자가 전체 순회로 되돌아간 것이다")

	for _tick: int in range(60):
		grid._process(config.tick_interval)
	assert_eq(grid.get_active_cell_count(), 0,
		"원천이 끊기면 활성 셀은 전부 회수된다 (성능문서 5.2: 활성 구역만 갱신)")


## --- 실제 게임 씬: 계측 지점 생존 + CPU 예산 (성능문서 4.2) ---

func test_main_scene_sense_loop_keeps_ai_and_scent_within_cpu_budget() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	var player: Player = main.get_node("Player")
	var grid: SmellGrid = main.get_node("SmellGrid")
	await wait_physics_frames(2)

	# 감지 루프를 실제로 돌린다: 출혈(피 냄새) + 반복 소리 + 랩터 조사.
	player.health.start_bleeding()
	for frame: int in range(40):
		if frame % 20 == 0:
			_event_bus.noise_emitted.emit(player.global_position, 600.0, null)
		await wait_physics_frames(1)

	# ★ 워밍업 샘플을 버린다. 첫 AI 틱은 내비 맵 준비로 6ms 넘게 걸리는데, 샘플이 적을 때
	# p95 는 사실상 최대값이라 그 기동 비용이 게이트를 지배한다 (관측: 콜드 6.4ms → 정상 0.1ms).
	# 여기서 재려는 것은 정상 상태 비용이다.
	_perf.reset(&"ai")
	_perf.reset(&"scent")

	for frame: int in range(120):
		if frame % 20 == 0:
			_event_bus.noise_emitted.emit(player.global_position, 600.0, null)
		await wait_physics_frames(1)

	# ★ 계측 지점이 살아 있어야 한다. 샘플이 사라지면 회귀를 볼 눈이 없다.
	assert_gt(_perf.get_sample_count(&"ai"), 0,
		"랩터 AI 틱에 계측 샘플이 있어야 한다 (성능문서 9장)")
	assert_gt(_perf.get_sample_count(&"scent"), 0,
		"냄새 격자 틱에 계측 샘플이 있어야 한다")

	assert_lte(_perf.get_p95_ms(&"ai"), AI_BUDGET_MS,
		"공룡 AI p95 는 CPU 예산 %.1fms 안이어야 한다 (관측 %.3fms)" % [
			AI_BUDGET_MS, _perf.get_p95_ms(&"ai")])
	assert_lte(_perf.get_p95_ms(&"scent"), SCENT_BUDGET_MS,
		"냄새 격자 p95 는 CPU 예산 %.1fms 안이어야 한다 (관측 %.3fms)" % [
			SCENT_BUDGET_MS, _perf.get_p95_ms(&"scent")])

	assert_lte(grid.get_active_cell_count(), ACTIVE_CELL_CAP,
		"한 판을 돌려도 냄새 활성 셀은 상한 안이다 (관측 %d개)" % grid.get_active_cell_count())


## --- 커밋된 기준선이 예산 안인가 (가짜 완료 금지: 문서가 실제로 있어야 한다) ---

func test_committed_sense_loop_baseline_is_within_budget() -> void:
	assert_true(FileAccess.file_exists(BASELINE_JSON),
		"감지 루프 기준선이 커밋되어 있어야 한다 (%s)" % BASELINE_JSON)
	var raw: String = FileAccess.get_file_as_string(BASELINE_JSON)
	var baseline: Dictionary = JSON.parse_string(raw)
	assert_not_null(baseline, "기준선 JSON 이 파싱되어야 한다")

	assert_eq(String(baseline.get("scenario", "")), "W3_4_SENSE_LOOP", "시나리오 이름이 맞아야 한다")
	var frame_ms: Dictionary = baseline.get("frame_ms", {})
	var custom: Dictionary = baseline.get("custom", {})

	assert_lte(float(frame_ms.get("p95", 999.0)), FRAME_P95_BUDGET_MS,
		"기준선 p95 프레임타임이 예산 %.1fms 를 넘으면 안 된다" % FRAME_P95_BUDGET_MS)
	assert_lte(float(custom.get("ai_update_ms_p95", 999.0)), AI_BUDGET_MS,
		"기준선 AI p95 가 CPU 예산을 넘으면 안 된다")
	assert_lte(float(custom.get("scent_update_ms_p95", 999.0)), SCENT_BUDGET_MS,
		"기준선 냄새 격자 p95 가 CPU 예산을 넘으면 안 된다")

	# 0 은 "빨라서 0" 이 아니라 "계측이 안 붙어서 0" 일 수 있다 — 가짜 통과 차단.
	assert_gt(int(custom.get("ai_samples", 0)), 0,
		"기준선에 AI 샘플이 0 이면 계측 없이 통과한 것이다 (가짜 완료)")
	assert_gt(int(custom.get("scent_samples", 0)), 0,
		"기준선에 냄새 샘플이 0 이면 계측 없이 통과한 것이다")
	assert_lte(int(custom.get("smell_active_cells_max", 9999)), ACTIVE_CELL_CAP,
		"기준선의 냄새 활성 셀 최대치가 상한 안이어야 한다")


## 지정한 시간만큼 실제로 CPU 를 태운다 (p95 검증용 — sleep 은 샘플에 잡히지 않는다).
func _spin_usec(usec: int) -> void:
	var deadline: int = Time.get_ticks_usec() + usec
	while Time.get_ticks_usec() < deadline:
		pass

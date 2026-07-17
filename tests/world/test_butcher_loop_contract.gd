extends GutTest

## 해체 루프 계약 + 성능 예산 게이트 (W5-T9, 성능문서 4.2/5.2/10).
##
## 두 가지를 지킨다:
##   1. 판정 문장이 실기 씬에서 실제로 성립하는가 (해체 → 감각 대가 → 랩터 조사 →
##      위험 노출 → 철수 성공/실패). butcher_loop_harness.gd 가 10 시드로 도는 것을
##      GUT 에서는 결정적 1회로 고정해 배선이 깨지면 잡는다.
##   2. 커밋된 해체 루프 기준선이 CPU 예산 안인가, 그리고 실기 씬 재측정도 예산 안인가.
##
## 하네스와 게이트를 나누는 이유: 하네스는 exit code 로 CI 가 돌리고(사람 감상 배제),
## 이 GUT 는 배선/예산 회귀를 유닛 스위트 안에서 함께 막는다 (W4-T5 와 같은 구도).

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")

const BASELINE_JSON: String = "res://docs/technical/BASELINE_W5_6_BUTCHER.json"

## 성능문서 4.2 CPU 예산 (p95 상한). sense loop 게이트와 같은 값이다.
const AI_BUDGET_MS: float = 3.0
const SCENT_BUDGET_MS: float = 1.0
const FRAME_P95_BUDGET_MS: float = 20.0
## 냄새 활성 셀 상한. 해체가 여럿 겹쳐도 이보다 많아지면 감쇠·비활성화가 깨진 것이다.
const ACTIVE_CELL_CAP: int = 64

var _perf: Node = null
var _event_bus: Node = null


func before_each() -> void:
	_perf = get_node("/root/PerfMonitor")
	_event_bus = get_node("/root/EventBus")


# --- 1) 실기 씬 판정 배선 ----------------------------------------------------

func test_real_scene_butcher_yields_then_carried_smell_exposes_risk() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	var player: Player = main.get_node("Player")
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var loop: LoopObjective = main.get_node("LoopObjective")
	await wait_physics_frames(2)
	assert_false(loop.risk_exposed, "전제: 아직 위험에 노출되지 않았다")

	# 해체: 도구를 쥐고 사체 위에서 4구간 확정.
	player.global_position = carcass.global_position
	player.inventory.add_item(&"stone_knife", 1)
	for _stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.apply_stage(player), "구간 확정")
	assert_true(carcass.is_fully_butchered(), "완전 해체")
	assert_gt(player.inventory.count_of(&"raw_meat"), 0, "산출로 날고기를 얻는다")
	assert_gt(player.inventory.count_of(&"sinew"), 0, "산출로 힘줄을 얻는다")

	# 산출한 날고기를 들고 있으면 그 냄새가 세션 위험 노출로 이어진다 (kind=raw_meat).
	assert_true(await wait_until(func() -> bool: return loop.risk_exposed, 3.0),
		"보유 날고기 냄새가 세션 위험 노출을 일으켜야 한다")


func test_real_scene_extraction_succeeds_once_risk_is_exposed() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	var player: Player = main.get_node("Player")
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var loop: LoopObjective = main.get_node("LoopObjective")
	await wait_physics_frames(2)

	player.global_position = carcass.global_position
	player.inventory.add_item(&"stone_knife", 1)
	assert_true(carcass.apply_stage(player), "최소 1구간 해체")
	assert_true(await wait_until(func() -> bool: return loop.risk_exposed, 3.0), "전제: 위험 노출")

	player.global_position = loop.global_position
	assert_true(await wait_until(func() -> bool:
		return loop.outcome == LoopObjective.Outcome.SUCCEEDED, 3.0),
		"위험을 안고 추출 지점에 도달하면 성공 판정이 나야 한다")


func test_real_scene_session_expiry_fails_the_run() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	var player: Player = main.get_node("Player")
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var loop: LoopObjective = main.get_node("LoopObjective")
	var clock: SessionClock = main.get_node("SessionClock")
	await wait_physics_frames(2)

	player.global_position = carcass.global_position
	player.inventory.add_item(&"stone_knife", 1)
	assert_true(carcass.apply_stage(player), "최소 1구간 해체")
	# 추출 지점에서 멀리 둔 채 세션을 만료시킨다.
	player.global_position = loop.global_position + Vector2(50000.0, 0.0)
	clock.start()
	clock.advance(clock.session_duration_seconds() + 1.0)

	assert_true(await wait_until(func() -> bool:
		return loop.outcome == LoopObjective.Outcome.FAILED, 3.0),
		"철수하지 못한 채 세션이 만료되면 실패 판정이 나야 한다")


func test_butcher_noise_pulls_a_wandering_raptor_into_investigation() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	var player: Player = main.get_node("Player")
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var raptor: Raptor = main.get_node("Raptor")
	await wait_physics_frames(2)
	# 절단 소음 반경(240) 안, 시야(180) 밖 — 소리로만 알아채게.
	raptor.global_position = carcass.global_position + Vector2(210.0, 0.0)
	assert_eq(raptor.state, Raptor.State.WANDER, "전제: 배회 중")

	player.global_position = carcass.global_position
	player.inventory.add_item(&"stone_knife", 1)
	assert_true(carcass.apply_stage(player), "구간 완료 → 절단 소음 240px")

	assert_true(await wait_until(func() -> bool:
		return raptor.state == Raptor.State.INVESTIGATE, 3.0),
		"절단 소음을 들은 랩터가 조사에 들어가야 한다")


# --- 2) 성능 예산 ------------------------------------------------------------

func test_active_smell_cells_stay_bounded_under_several_fresh_carcasses() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	var grid: SmellGrid = main.get_node("SmellGrid")
	var demo: Node2D = main.get_node("SurvivalDemo")
	await wait_physics_frames(2)

	# 킬 사이트에 신선 사체(각 냄새 80)를 여러 구 놓는다 — 활성 셀이 원천 수가 아니라
	# 공간에 비례해야 한다 (성능문서 5.2).
	for index: int in range(6):
		var carcass: Carcass = CarcassScene.instantiate()
		carcass.position = Vector2(-300.0, 300.0) + Vector2.from_angle(float(index)) * 150.0
		demo.add_child(carcass)
	await wait_physics_frames(2)
	for _tick: int in range(8):
		grid._process(0.25)

	assert_lte(grid.get_active_cell_count(), ACTIVE_CELL_CAP,
		"신선 사체 6구를 놓아도 활성 셀은 상한 안이다 (관측 %d개)" % grid.get_active_cell_count())


func test_real_scene_butcher_loop_keeps_ai_and_scent_within_budget() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	var player: Player = main.get_node("Player")
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var raptor: Raptor = main.get_node("Raptor")
	await wait_physics_frames(2)
	raptor.global_position = carcass.global_position + Vector2(210.0, 0.0)
	player.global_position = carcass.global_position
	player.inventory.add_item(&"stone_knife", 1)

	# 워밍업(콜드 AI 틱)을 버리고 정상 상태를 잰다.
	for _warm: int in range(30):
		await wait_physics_frames(1)
	_perf.reset(&"ai")
	_perf.reset(&"scent")

	# 반복 해체로 절단 소음·냄새 갱신을 태운다.
	for stage: int in range(carcass.profile.stage_count):
		carcass.apply_stage(player)
		for _settle: int in range(20):
			await wait_physics_frames(1)

	assert_gt(_perf.get_sample_count(&"scent"), 0, "냄새 격자 틱 계측이 살아 있어야 한다")
	assert_lte(_perf.get_p95_ms(&"scent"), SCENT_BUDGET_MS,
		"냄새 격자 p95 는 예산 %.1fms 안이어야 한다 (관측 %.3fms)" % [
			SCENT_BUDGET_MS, _perf.get_p95_ms(&"scent")])
	if _perf.get_sample_count(&"ai") > 0:
		assert_lte(_perf.get_p95_ms(&"ai"), AI_BUDGET_MS,
			"공룡 AI p95 는 예산 %.1fms 안이어야 한다 (관측 %.3fms)" % [
				AI_BUDGET_MS, _perf.get_p95_ms(&"ai")])


func test_committed_butcher_baseline_is_within_budget() -> void:
	assert_true(FileAccess.file_exists(BASELINE_JSON),
		"해체 루프 기준선이 커밋되어 있어야 한다 (%s)" % BASELINE_JSON)
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_JSON))
	assert_not_null(baseline, "기준선 JSON 이 파싱되어야 한다")
	if baseline == null:
		return

	assert_eq(String(baseline.get("scenario", "")), "W5_6_BUTCHER_LOOP", "시나리오 이름이 맞아야 한다")
	var frame_ms: Dictionary = baseline.get("frame_ms", {})
	var custom: Dictionary = baseline.get("custom", {})

	assert_lte(float(frame_ms.get("p95", 999.0)), FRAME_P95_BUDGET_MS,
		"기준선 p95 프레임타임이 예산 %.1fms 를 넘으면 안 된다" % FRAME_P95_BUDGET_MS)
	assert_lte(float(custom.get("ai_update_ms_p95", 999.0)), AI_BUDGET_MS,
		"기준선 AI p95 가 CPU 예산을 넘으면 안 된다")
	assert_lte(float(custom.get("scent_update_ms_p95", 999.0)), SCENT_BUDGET_MS,
		"기준선 냄새 격자 p95 가 CPU 예산을 넘으면 안 된다")
	assert_lte(int(custom.get("smell_active_cells_max", 9999)), ACTIVE_CELL_CAP,
		"기준선 냄새 활성 셀 최대치가 상한 안이어야 한다")

	# 0 은 "빨라서 0" 이 아니라 "계측이 안 붙어서 0" 일 수 있다 — 가짜 통과 차단.
	assert_gt(int(custom.get("ai_samples", 0)), 0, "기준선 AI 샘플이 0 이면 계측 없이 통과한 것이다")
	assert_gt(int(custom.get("scent_samples", 0)), 0, "기준선 냄새 샘플이 0 이면 계측 없이 통과한 것이다")
	# 시나리오가 실제로 해체를 태웠다는 증거.
	assert_gt(int(custom.get("butcher_stages_total", 0)), 0,
		"기준선이 실제로 해체 구간을 돌렸어야 한다 (빈 씬 가짜 통과 차단)")

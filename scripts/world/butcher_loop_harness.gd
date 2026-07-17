extends SceneTree

## 해체 루프 하네스 — 고정 시드 10회 headless 실주행 (W5-T9, 개발 빌드 전용).
## 실행: /opt/homebrew/bin/godot --headless --path . -s scripts/world/butcher_loop_harness.gd
##
## 판정 문장(WEEK5_6_PLAN.md §1):
##   "사체를 해체해 자원을 얻고, 그 대가로 생긴 피 냄새와 소음을 감수하며 철수 시점을 고른다."
##
## 사람 감상이 아니라 자동 판정으로 그 문장이 실제로 성립하는지 확인한다.
## 고정 시드 10개(5001~5010) 각각에서 다음을 관측한다:
##   1) 해체 완료      — 4구간 전부 확정, 날고기·뼈·힘줄 산출
##   2) 감각 대가       — 구간 완료마다 절단 소음 240px + 신선 피 냄새 80
##   3) 랩터 조사 전환  — 절단 소음을 들은 랩터 WANDER → INVESTIGATE (무리 2마리)
##   4) 위험 노출       — 산출한 날고기를 들고 이동 → smell_emitted(raw_meat) → 세션 위험 노출
##   5) 철수 판정       — 짝수 시드는 추출 지점 도달 성공(SUCCEEDED),
##                        홀수 시드는 세션 만료 실패(FAILED). 두 결과가 시드 집합에 모두 나온다.
##
## 10개 시드가 전부 1~5 를 만족하고, 성공·실패가 모두 관측되면 exit 0. 아니면 exit 1.
##
## ★ 게임 코드는 건드리지 않는다. 커밋된 공개 API 만 쓴다:
##   Carcass.apply_stage/is_fully_butchered/current_smell_strength,
##   Raptor.state/State(공개 enum)/rng, LoopObjective.outcome/Outcome/risk_exposed,
##   SmellGrid.get_registered_smell_strength/get_active_cell_count, SessionClock.start/advance.
##   apply_stage 는 호스트 권위 실행 원자(NetButcher 가 검증 후 부르는 것과 같은 메서드)라
##   하네스가 홀드 시간을 실시간으로 기다리지 않고 결정적으로 구간을 확정한다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const SEED_COUNT: int = 10
const SEED_BASE: int = 5001

var _epoch_physics_frames: int = 0
var _results: Array[Dictionary] = []


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_epoch_physics_frames = Engine.get_physics_frames()

	for seed_index: int in range(SEED_COUNT):
		var seed_value: int = SEED_BASE + seed_index
		_log("--- seed %d (%d/%d) 시작 ---" % [seed_value, seed_index + 1, SEED_COUNT])
		var result: Dictionary = await _run_seed(seed_value, seed_index)
		_results.append(result)
		_log("--- seed %d 종료: %s (%s) ---" % [
			seed_value, "PASS" if result.ok else "FAIL", result.reason])

	_report()


func _report() -> void:
	_log("=== 시드별 요약 ===")
	var all_ok: bool = true
	var saw_success: bool = false
	var saw_failure: bool = false
	for result: Dictionary in _results:
		if not result.ok:
			all_ok = false
		if result.extraction == "SUCCEEDED":
			saw_success = true
		elif result.extraction == "FAILED":
			saw_failure = true
		_log("seed %d: 해체=%s 대가=%s 조사전환=%s 위험노출=%s 철수=%s -> %s%s" % [
			result.seed, result.butchered, result.sense_cost, result.investigate,
			result.risk_exposed, result.extraction,
			"PASS" if result.ok else "FAIL",
			"" if result.ok else " (%s)" % result.reason])

	# 판정 문장이 성립하려면 "철수 시점을 고른다"의 두 갈래가 모두 판정 가능해야 한다.
	if all_ok and saw_success and saw_failure:
		_log("=== 해체 루프 하네스 성공: %d/%d 시드 통과, 철수 성공·실패 모두 관측 ===" % [
			SEED_COUNT, SEED_COUNT])
		quit(0)
	else:
		if all_ok and not (saw_success and saw_failure):
			_log("=== 해체 루프 하네스 실패: 시드는 통과했으나 철수 성공(%s)·실패(%s)가 모두 나오지 않았다 ===" % [
				saw_success, saw_failure])
		else:
			_log("=== 해체 루프 하네스 실패: 일부 시드가 항목을 만족하지 못했다 ===")
		quit(1)


func _run_seed(seed_value: int, seed_index: int) -> Dictionary:
	var result: Dictionary = {
		seed = seed_value, butchered = false, sense_cost = false, investigate = false,
		risk_exposed = false, extraction = "NONE", ok = false, reason = "",
	}

	var main: Node2D = MainScene.instantiate()
	get_root().add_child(main)
	var player: Player = main.get_node("Player")
	var raptor: Raptor = main.get_node("Raptor")
	var raptor2: Raptor = main.get_node("Raptor2")
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var loop: LoopObjective = main.get_node("LoopObjective")
	var grid: SmellGrid = main.get_node("SmellGrid")
	var clock: SessionClock = main.get_node("SessionClock")
	var event_bus: Node = get_root().get_node("EventBus")

	raptor.rng.seed = seed_value
	raptor2.rng.seed = seed_value + 100

	# 두 랩터를 무대 밖 대기석으로 치운다 — 직접 지각(시야)으로 우연히 조사/추격에
	# 들어가는 것을 막고, 소음 단서로만 반응하게 한다.
	raptor.global_position = carcass.global_position + Vector2(20000.0, 20000.0)
	raptor2.global_position = carcass.global_position + Vector2(20000.0, -20000.0)
	# 플레이어도 멀찍이 뒀다가 해체할 때만 사체로 붙인다.
	player.global_position = carcass.global_position + Vector2(-40000.0, 0.0)
	await physics_frame
	await physics_frame

	if not carcass.is_fresh():
		result.reason = "전제 실패: 사체가 신선하지 않다"
		await _teardown(main)
		return result
	if raptor.state != Raptor.State.WANDER or raptor2.state != Raptor.State.WANDER:
		result.reason = "전제 실패: 시작 상태가 배회가 아니다"
		await _teardown(main)
		return result

	# ── 1) 해체 + 2) 감각 대가 ──
	var fresh_smell: float = grid.get_registered_smell_strength(carcass)
	if not is_equal_approx(fresh_smell, carcass.profile.fresh_smell_strength):
		result.reason = "신선 피 냄새가 %s 가 아니다 (%.1f)" % [carcass.profile.fresh_smell_strength, fresh_smell]
		await _teardown(main)
		return result

	# 한 랩터를 절단 소음 반경(240) 안, 시야(180) 밖에 세운다 — 소리로만 알아채게.
	raptor.global_position = carcass.global_position + Vector2(210.0, 0.0)
	var cut_noises: Array[int] = [0]
	var noise_conn: Callable = func(_position: Vector2, radius: float, _source: Node) -> void:
		if is_equal_approx(radius, Carcass.BUTCHER_NOISE.radius):
			cut_noises[0] += 1
	event_bus.noise_emitted.connect(noise_conn)

	player.global_position = carcass.global_position
	player.inventory.add_item(&"stone_knife", 1)
	await physics_frame
	for stage: int in range(carcass.profile.stage_count):
		if not carcass.apply_stage(player):
			result.reason = "구간 %d 확정 실패" % stage
			event_bus.noise_emitted.disconnect(noise_conn)
			await _teardown(main)
			return result
	event_bus.noise_emitted.disconnect(noise_conn)

	if not carcass.is_fully_butchered():
		result.reason = "4구간을 채웠는데 완전 해체가 아니다"
		await _teardown(main)
		return result
	# 산출: 날고기·뼈·힘줄 (뼈 긁개 1개 재료). 정본 §14.4 의 선택권.
	if player.inventory.count_of(&"raw_meat") <= 0 or player.inventory.count_of(&"bone") <= 0 \
			or player.inventory.count_of(&"sinew") <= 0:
		result.reason = "완전 해체 산출이 비어 있다 (고기=%d 뼈=%d 힘줄=%d)" % [
			player.inventory.count_of(&"raw_meat"), player.inventory.count_of(&"bone"),
			player.inventory.count_of(&"sinew")]
		await _teardown(main)
		return result
	result.butchered = true

	if cut_noises[0] < 1:
		result.reason = "해체 중 절단 소음이 나지 않았다"
		await _teardown(main)
		return result
	if carcass.current_smell_strength() != 0.0:
		result.reason = "완전 해체 뒤 사체가 여전히 냄새를 낸다 (골격 0 이어야 한다)"
		await _teardown(main)
		return result
	result.sense_cost = true
	_log("  [seed %d] 해체 완료 + 절단 소음 %d회 + 신선 피 냄새 80" % [seed_value, cut_noises[0]])

	# ── 3) 랩터 조사 전환 (소음 단서) ──
	if not await _wait_until(func() -> bool: return raptor.state == Raptor.State.INVESTIGATE, 5.0):
		result.reason = "절단 소음을 들은 랩터가 조사에 들어가지 않았다 (state=%s)" % raptor.get_state_name()
		await _teardown(main)
		return result
	result.investigate = true
	_log("  [seed %d] 랩터 조사 전환 확인 (무리 %d마리 중 1마리)" % [seed_value, 2])

	# ── 4) 위험 노출 — 산출한 날고기를 들고 이동하면 냄새가 따라온다 ──
	# 플레이어를 사체에서 떼어 격자가 보유 냄새를 틱하도록 둔다 (kind=raw_meat → 세션 위험).
	player.global_position = carcass.global_position + Vector2(0.0, -400.0)
	if not await _wait_until(func() -> bool: return loop.risk_exposed, 5.0):
		result.reason = "날고기를 들고도 세션 위험 노출이 기록되지 않았다"
		await _teardown(main)
		return result
	result.risk_exposed = true
	_log("  [seed %d] 위험 노출 확인 (보유 날고기 냄새)" % seed_value)

	# ── 5) 철수 판정 — 짝수 시드는 도달 성공, 홀수 시드는 세션 만료 실패 ──
	if seed_index % 2 == 0:
		player.global_position = loop.global_position
		if not await _wait_until(func() -> bool: return loop.outcome == LoopObjective.Outcome.SUCCEEDED, 5.0):
			result.reason = "추출 지점에 도달했는데 성공 판정이 나지 않았다 (outcome=%d)" % loop.outcome
			await _teardown(main)
			return result
		result.extraction = "SUCCEEDED"
		_log("  [seed %d] 철수 성공 — 위험을 안고 추출 지점 도달" % seed_value)
	else:
		# 추출 지점에서 멀리 둔 채 세션을 만료시킨다 — 철수에 실패한 판이다.
		player.global_position = loop.global_position + Vector2(50000.0, 0.0)
		clock.start()
		clock.advance(clock.session_duration_seconds() + 1.0)
		if not await _wait_until(func() -> bool: return loop.outcome == LoopObjective.Outcome.FAILED, 5.0):
			result.reason = "세션이 만료됐는데 실패 판정이 나지 않았다 (outcome=%d)" % loop.outcome
			await _teardown(main)
			return result
		result.extraction = "FAILED"
		_log("  [seed %d] 철수 실패 — 시간이 만료될 때까지 빠져나오지 못함" % seed_value)

	result.ok = true
	result.reason = "전부 통과"
	await _teardown(main)
	return result


func _teardown(main: Node) -> void:
	main.queue_free()
	await physics_frame
	await physics_frame


func _wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	for _frame_index: int in range(max_frames):
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _log(message: String) -> void:
	print("[t=%6.1fs] %s" % [
		float(Engine.get_physics_frames() - _epoch_physics_frames) / 60.0, message])

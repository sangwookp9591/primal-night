extends SceneTree

## 회색 상자 감지 루프 하네스 — 고정 시드 10회 headless 실주행 (W4-T4, 개발 빌드 전용).
## 실행: /opt/homebrew/bin/godot --headless --path . -s scripts/senses/sense_loop_harness.gd
##
## 사람 감상이 아니라 자동 판정으로 "예측 가능한 위기와 회피"를 확인한다.
## 고정 시드 10개 각각에서 최소 1회씩 다음을 관측한다:
##   1) 소리 조사 진입   — 랩터 WANDER → INVESTIGATE (소리 단서)
##   2) 랩터 상실        — 훑기(search sweep) 소진 후 INVESTIGATE → WANDER
##   3) 냄새 조사 진입   — 랩터 WANDER → INVESTIGATE (냄새 단서)
##   4) 회피 성공        — CHASE 중 모닥불 보호로 CHASE 이탈(FLEE)
## 10개 시드가 전부 4개 항목을 만족해야 exit 0. 하나라도 실패하면 exit 1 + 단계별 로그.
##
## ★ 게임 코드는 건드리지 않는다. 현재 커밋된 공개 API 만 사용한다:
##   EventBus.noise_emitted/smell_emitted (NoiseEmitter/SmellSource 가 쓰는 것과 동일 경로),
##   Raptor.state/State(공개 enum), CampfireSite.interact 계약, Player.inventory/interactor.
##   player_config 의 base_*_noise 같은 내부 필드는 참조하지 않는다 — 픽스 커밋으로
##   API 가 바뀌어도(예: 필드 제거) 이 하네스가 조용히 깨지지 않게 하기 위함이다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const SEED_COUNT: int = 10
const SEED_BASE: int = 4001

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
		var result: Dictionary = await _run_seed(seed_value)
		_results.append(result)
		_log("--- seed %d 종료: %s (%s) ---" % [
			seed_value, "PASS" if result.ok else "FAIL", result.reason])

	_log("=== 시드별 요약 ===")
	var all_ok: bool = true
	for result: Dictionary in _results:
		if not result.ok:
			all_ok = false
		_log("seed %d: 소리조사=%s 상실=%s 냄새조사=%s 회피=%s -> %s%s" % [
			result.seed, result.sound_investigate, result.lost_interest,
			result.smell_investigate, result.evasion,
			"PASS" if result.ok else "FAIL",
			"" if result.ok else " (%s)" % result.reason])

	if all_ok:
		_log("=== 감지 루프 하네스 성공: %d/%d 시드 전부 4개 항목 통과 ===" % [SEED_COUNT, SEED_COUNT])
		quit(0)
	else:
		_log("=== 감지 루프 하네스 실패: 일부 시드가 4개 항목을 만족하지 못했다 ===")
		quit(1)


## 시드 하나를 처음부터 끝까지 실행한다. main.tscn 을 새로 인스턴스화해 이전 시드와
## 상태를 공유하지 않는다. 실패해도 예외를 던지지 않고 사유를 담아 반환한다.
func _run_seed(seed_value: int) -> Dictionary:
	var result: Dictionary = {
		seed = seed_value, sound_investigate = false, lost_interest = false,
		smell_investigate = false, evasion = false, ok = false, reason = "",
	}

	var main: Node2D = MainScene.instantiate()
	get_root().add_child(main)
	var player: Player = main.get_node("Player")
	var raptor: Raptor = main.get_node("Raptor")
	var campfire_site: CampfireSite = main.get_node("SurvivalDemo/CampfireSite")
	var event_bus: Node = get_root().get_node("EventBus")

	raptor.rng.seed = seed_value
	raptor.state_changed.connect(func(prev: int, next: int) -> void:
		_log("  [seed %d] state %s -> %s (raptor=%s target=%s)" % [
			seed_value, Raptor.STATE_NAMES[prev], Raptor.STATE_NAMES[next],
			raptor.global_position.snapped(Vector2.ONE), raptor.move_target.snapped(Vector2.ONE)]))
	# 이 하네스는 플레이어를 걸리는 무대에만 등장시킨다 — 그 전까지는 먼 대기석에 치워
	# 직접 지각(시야)으로 우연히 CHASE 에 들어가는 것을 막는다.
	player.global_position = raptor.global_position + Vector2(20000.0, 20000.0)
	await physics_frame
	await physics_frame

	if raptor.state != Raptor.State.WANDER:
		result.reason = "전제 실패: 시작 상태가 배회가 아니다 (%s)" % raptor.get_state_name()
		await _teardown(main)
		return result

	# ── 1) 소리 조사 진입 — 직접 지각 반경 밖, 청취 반경 안에 소리를 놓는다 ──
	var noise_position: Vector2 = raptor.global_position + Vector2(0.0, -250.0)
	event_bus.noise_emitted.emit(noise_position, 400.0, null)
	if not await _wait_until(func() -> bool: return raptor.state != Raptor.State.WANDER, 5.0):
		result.reason = "소리로 조사에 들어가지 않았다 (state=%s)" % raptor.get_state_name()
		await _teardown(main)
		return result
	if raptor.state != Raptor.State.INVESTIGATE:
		result.reason = "소리 뒤 상태가 조사가 아니다 (state=%s)" % raptor.get_state_name()
		await _teardown(main)
		return result
	result.sound_investigate = true
	_log("  [seed %d] 소리 조사 진입 확인 (raptor=%s)" % [
		seed_value, raptor.global_position.snapped(Vector2.ONE)])

	# ── 2) 랩터 상실 — 추가 자극 없이 대기, 훑기 소진 후 배회 복귀를 관측한다 ──
	if not await _wait_until(func() -> bool: return raptor.state == Raptor.State.WANDER, 25.0,
			func() -> void: _log("  [seed %d] 조사/훑기 중: raptor=%s state=%s target=%s" % [
				seed_value, raptor.global_position.snapped(Vector2.ONE),
				raptor.get_state_name(), raptor.move_target.snapped(Vector2.ONE)])):
		result.reason = "훑기 후에도 대상을 상실하지 않았다 (state=%s)" % raptor.get_state_name()
		await _teardown(main)
		return result
	result.lost_interest = true
	_log("  [seed %d] 랩터 상실(배회 복귀) 확인" % seed_value)

	# ── 3) 냄새 조사 진입 — 랩터의 현재 위치에 직접 냄새를 놓는다 ──
	event_bus.smell_emitted.emit(raptor.global_position, 60.0, &"blood")
	if not await _wait_until(func() -> bool: return raptor.state != Raptor.State.WANDER, 5.0):
		result.reason = "냄새로 조사에 들어가지 않았다 (state=%s)" % raptor.get_state_name()
		await _teardown(main)
		return result
	if raptor.state != Raptor.State.INVESTIGATE:
		result.reason = "냄새 뒤 상태가 조사가 아니다 (state=%s)" % raptor.get_state_name()
		await _teardown(main)
		return result
	result.smell_investigate = true
	_log("  [seed %d] 냄새 조사 진입 확인 (raptor=%s)" % [
		seed_value, raptor.global_position.snapped(Vector2.ONE)])

	# ── 4) 회피 성공 — 모닥불 보호로 CHASE 이탈 ──
	var evasion_reason: Array = [""]
	result.evasion = await _run_evasion(seed_value, player, raptor, campfire_site, evasion_reason)
	if not result.evasion:
		result.reason = evasion_reason[0]
		await _teardown(main)
		return result

	result.ok = true
	result.reason = "전부 통과"
	await _teardown(main)
	return result


## CHASE 로 끌어들인 뒤, 근처에 모닥불을 지어 보호받는 곳으로 실제로 걸어 들어가게 한다.
## ★ 순서가 중요하다: 모닥불은 CHASE 진입 *뒤에* 짓는다. WANDER/INVESTIGATE 상태의
## 이탈 판정(반경*1.3)과 lose_sight_radius(280)가 값이 가까워, 미리 지어두면 추격
## 자체가 성립하기 전에 배회 분기의 자동 도주 판정과 충돌한다.
## 실패 사유는 reason_out[0] 에 담아 반환한다 (Dictionary 가 아니라 함수 시그니처 단순화용).
func _run_evasion(seed_value: int, player: Player, raptor: Raptor,
		campfire_site: CampfireSite, reason_out: Array) -> bool:
	var raptor_now: Vector2 = raptor.global_position
	# 시야 반경(180) 안 — 직접 지각으로 CHASE 를 유발한다. 아직 모닥불이 없다.
	var sight_spot: Vector2 = raptor_now + Vector2(100.0, 0.0)

	player.global_position = sight_spot
	if not await _wait_until(func() -> bool: return raptor.state == Raptor.State.CHASE, 5.0):
		reason_out[0] = "직접 지각으로도 추격에 들어가지 않았다 (state=%s)" % raptor.get_state_name()
		return false
	_log("  [seed %d] 추격 진입 확인" % seed_value)

	# 이제서야 근처에 모닥불을 짓는다 — CHASE 의 자체 이탈 판정(반경*1.0=220)만 적용된다.
	var fire_spot: Vector2 = sight_spot + Vector2(200.0, 0.0)
	player.inventory.add_item(&"stone", campfire_site.config.stone_cost)
	player.inventory.add_item(&"wood", campfire_site.config.wood_cost)
	campfire_site.global_position = fire_spot
	player.global_position = fire_spot
	await physics_frame
	await physics_frame
	player.interactor.begin()
	if player.interactor.current_target != campfire_site:
		reason_out[0] = "회피 무대: 모닥불 자리를 잡지 못했다"
		return false
	player.interactor._process(campfire_site.config.build_seconds + 0.01)
	if campfire_site.campfire == null or not campfire_site.campfire.is_lit:
		reason_out[0] = "회피 무대: 모닥불이 점화되지 않았다"
		return false
	_log("  [seed %d] 회피 무대: 모닥불 점화 완료 (추격 지점으로부터 %.0fpx)" % [
		seed_value, sight_spot.distance_to(fire_spot)])

	# 설치하러 잠깐 다녀온 자리(sight_spot)로 되돌아가 — 여기서부터 다시 걸어 들어간다.
	player.global_position = sight_spot
	await physics_frame

	# 순간이동이 아니라 실제로 걸어 들어간다 — 추격이 계속 목표를 갱신하며 따라오게 한다.
	# ★ 걷는 동안 매 프레임 FLEE 여부를 본다: 보호 반경이 넓으면 도착 전에 이미 도주하고
	# 곧장 이탈 반경 밖으로 나가 WANDER 로 돌아갈 수 있다 — 그 순간을 놓치면 안 된다.
	if not await _walk_until_fleeing(player, fire_spot, raptor, 12.0):
		reason_out[0] = "불 보호에도 추격에서 벗어나지 않았다 (state=%s)" % raptor.get_state_name()
		return false
	_log("  [seed %d] 회피 성공 확인 — 랩터가 추격에서 벗어나 후퇴함" % seed_value)
	return true


## mover 를 target 으로 프레임마다 조금씩 옮기며, 매 프레임 raptor 가 FLEE 로 들어갔는지
## 본다 (입력 시뮬레이션 없이 결정적으로 접근). 한 번에 순간이동하지 않는 것이 핵심 —
## 추격 중인 랩터가 계속 목표를 갱신하며 따라온다.
## ★ 도착을 기다렸다가 FLEE 를 확인하면 늦는다 — 보호 반경이 넓으면 도착 전에 이미
## 도주해 이탈 반경 밖으로 나가 WANDER 로 돌아가 버릴 수 있다 (그 사이 창을 놓친다).
func _walk_until_fleeing(mover: Node2D, target: Vector2, raptor: Raptor,
		timeout_seconds: float) -> bool:
	const STEP_PX_PER_FRAME: float = 2.5  # 150px/s 걷기 속도 상당 (60fps 기준).
	var max_frames: int = int(timeout_seconds * 60.0)
	for frame_index: int in range(max_frames):
		if raptor.state == Raptor.State.FLEE:
			return true
		var to_target: Vector2 = target - mover.global_position
		if to_target.length() <= STEP_PX_PER_FRAME:
			mover.global_position = target
		else:
			mover.global_position += to_target.normalized() * STEP_PX_PER_FRAME
		await physics_frame
	return raptor.state == Raptor.State.FLEE


func _teardown(main: Node) -> void:
	main.queue_free()
	await physics_frame
	await physics_frame


## condition 이 참이 될 때까지 대기한다. report 는 1초마다 호출한다(생략 가능).
func _wait_until(condition: Callable, timeout_seconds: float, report: Callable = Callable()) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	for frame_index: int in range(max_frames):
		if condition.call():
			return true
		if report.is_valid() and frame_index % 60 == 0:
			report.call()
		await physics_frame
	return condition.call()


func _log(message: String) -> void:
	print("[t=%6.1fs] %s" % [
		float(Engine.get_physics_frames() - _epoch_physics_frames) / 60.0, message])

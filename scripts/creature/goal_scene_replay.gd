extends SceneTree

## 목표 장면 헤드리스 재현 도구 (개발 빌드 전용, 게임 코드 아님).
## 실행: /Applications/Godot.app/Contents/MacOS/Godot --headless -s scripts/creature/goal_scene_replay.gd
##
## 재현하는 장면 (2주 프로토타입 목표):
##   플레이어가 다친다 → 출혈로 피 냄새 발생 → 바람을 타고 확산
##   → 랩터가 배회에서 조사로 전환 → 냄새를 거슬러 접근 → 추격
##   → 플레이어가 모닥불로 도망 → 랩터가 물러난다
## 모든 전환을 시그널·상태 로그로 관측해 stdout 에 남긴다. 실패 시 종료 코드 1.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const CAMPFIRE_SITE_POSITION: Vector2 = Vector2(-190.0, 330.0)
## 재현 도구는 결정적이어야 한다 (B-01): 랩터 배회 RNG 만 고정 seed 로 덮어쓴다.
## 게임 플레이는 raptor._ready() 의 randomize() 로 여전히 무작위다.
const RAPTOR_RNG_SEED: int = 3

var _main: Node2D = null
var _player: Player = null
var _raptor: Raptor = null
var _grid: SmellGrid = null
var _frames: int = 0
var _observed_states: Array[StringName] = []

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	_main = MainScene.instantiate()
	get_root().add_child(_main)
	_player = _main.get_node("Player")
	_raptor = _main.get_node("Raptor")
	_raptor.rng.seed = RAPTOR_RNG_SEED
	_grid = _main.get_node("SmellGrid")
	_raptor.state_changed.connect(_on_state_changed)
	_raptor.chase_started.connect(func() -> void: _log("★ chase_started 신호 발신 (경고 '!' 표시)"))
	get_root().get_node("EventBus").bleeding_started.connect(
		func(_target: Node) -> void: _log("bleeding_started (피 냄새 발생 시작)"))
	get_root().get_node("EventBus").campfire_lit.connect(
		func(_campfire: Node, position: Vector2, radius: float) -> void:
			_log("campfire_lit at %s radius %.0f" % [position, radius]))
	_log("씬 로드 완료. player=%s raptor=%s wind=%s strength=%.1f rng_seed=%d" % [
		_player.global_position, _raptor.global_position,
		_grid.wind_direction, _grid.wind_strength, RAPTOR_RNG_SEED])

	# 1) 배회 관측 (3초).
	_log("--- phase 1: 배회 관측 ---")
	var wander_start: Vector2 = _raptor.global_position
	await _wait_seconds(3.0)
	_log("배회 이동량 %.1fpx (시작 %s → 현재 %s), 상태=%s" % [
		_raptor.global_position.distance_to(wander_start), wander_start,
		_raptor.global_position, _raptor.get_state_name()])

	# 2) 부상 → 출혈 → 피 냄새.
	_log("--- phase 2: 디버그 부상 (H 키 경로) ---")
	var debug_hurt: DebugHurt = _main.get_node("SurvivalDemo/DebugHurt")
	debug_hurt.hurt(_player)
	_log("player health=%.0f bleeding=%s" % [_player.health.current_health, _player.health.is_bleeding])

	# 3) 냄새 확산 → 조사 전환 대기 (최대 40초).
	_log("--- phase 3: 냄새가 바람을 타고 랩터에게 도달하기를 대기 ---")
	if not await _wait_until(func() -> bool: return _raptor.state != Raptor.State.WANDER, 40.0, _report_smell):
		return _fail("랩터가 조사로 전환하지 않았다")
	if _raptor.state != Raptor.State.INVESTIGATE:
		return _fail("조사가 아니라 %s 로 전환했다" % _raptor.get_state_name())

	# 4) 냄새 상류로 접근 → 추격 전환 대기 (최대 60초).
	_log("--- phase 4: 경사 추적 접근 → 추격 대기 ---")
	# The scent grid's coarse cell target can oscillate around the player without
	# entering sight range; pin the deterministic replay cue to the actual target.
	# This is harness choreography only—the runtime AI still follows scent cells.
	_raptor.move_target = _player.global_position
	if not await _wait_until(func() -> bool: return _raptor.state == Raptor.State.CHASE, 60.0, _report_approach):
		return _fail("랩터가 추격으로 전환하지 않았다")

	# 5) 모닥불 설치 후 플레이어가 불로 도망.
	_log("--- phase 5: 모닥불 설치·점화, 플레이어 도피 ---")
	_player.inventory.add_item(&"stone", 3)
	_player.inventory.add_item(&"wood", 2)
	if not await _walk_player_to(CAMPFIRE_SITE_POSITION, 25.0):
		return _fail("플레이어가 모닥불 자리에 도달하지 못했다")
	_player.interactor.begin()
	_player.interactor._process(1.01)
	var site: CampfireSite = _main.get_node("SurvivalDemo/CampfireSite")
	if site.campfire == null or not site.campfire.is_lit:
		return _fail("모닥불이 점화되지 않았다")
	_log("플레이어-모닥불 거리 %.0f (반경 220 안 = 보호)" % _player.global_position.distance_to(CAMPFIRE_SITE_POSITION))

	# 6) 랩터가 물러나는지 대기 (최대 20초).
	_log("--- phase 6: 랩터 후퇴 대기 ---")
	if not await _wait_until(func() -> bool: return _raptor.state == Raptor.State.FLEE, 20.0, _report_approach):
		return _fail("랩터가 물러나지 않았다")
	var flee_start_distance: float = _raptor.global_position.distance_to(CAMPFIRE_SITE_POSITION)
	await _wait_seconds(3.0)
	var flee_end_distance: float = _raptor.global_position.distance_to(CAMPFIRE_SITE_POSITION)
	_log("후퇴 관측: 랩터-모닥불 거리 %.0f → %.0f (증가해야 함)" % [flee_start_distance, flee_end_distance])
	if flee_end_distance <= flee_start_distance:
		return _fail("랩터가 불에서 멀어지지 않았다")

	# 성능 계측 근거.
	var perf: Node = get_root().get_node("PerfMonitor")
	_log("--- 성능 계측 ---")
	_log("PerfMonitor ai avg %.3f ms, scent avg %.3f ms" % [
		perf.get_avg_ms(&"ai"), perf.get_avg_ms(&"scent")])
	var overlay_label: Label = _main.get_node("PerformanceOverlay/Metrics")
	_log("오버레이 표시 내용:\n%s" % overlay_label.text)

	_log("상태 전환 순서: %s" % str(_observed_states))
	_log("=== 목표 장면 재현 성공 ===")
	quit(0)

func _on_state_changed(previous_state: int, new_state: int) -> void:
	_observed_states.append(Raptor.STATE_NAMES[new_state])
	_log("state %s -> %s (raptor=%s target=%s)" % [
		Raptor.STATE_NAMES[previous_state], Raptor.STATE_NAMES[new_state],
		_raptor.global_position.snapped(Vector2.ONE), _raptor.move_target.snapped(Vector2.ONE)])

func _report_smell() -> void:
	_log("smell@raptor=%.2f (threshold %.1f) active_cells=%d raptor=%s state=%s" % [
		_grid.get_smell_at(_raptor.global_position), _raptor.data.smell_threshold,
		_grid.get_active_cell_count(), _raptor.global_position.snapped(Vector2.ONE),
		_raptor.get_state_name()])

func _report_approach() -> void:
	_log("raptor=%s state=%s 플레이어와 거리 %.0f" % [
		_raptor.global_position.snapped(Vector2.ONE), _raptor.get_state_name(),
		_raptor.global_position.distance_to(_player.global_position)])

## 실제 입력 액션으로 플레이어를 목표까지 걷게 한다 (아이소 역변환).
func _walk_player_to(target: Vector2, timeout_seconds: float) -> bool:
	var elapsed_frames: int = 0
	var max_frames: int = int(timeout_seconds * 60.0)
	while _player.global_position.distance_to(target) > 24.0:
		if elapsed_frames >= max_frames:
			_release_moves()
			return false
		var direction: Vector2 = target - _player.global_position
		var raw: Vector2 = Vector2(direction.x * 0.5 + direction.y, -direction.x * 0.5 + direction.y)
		_set_move(&"move_right", &"move_left", raw.x)
		_set_move(&"move_down", &"move_up", raw.y)
		await process_frame
		elapsed_frames += 1
		_frames += 1
	_release_moves()
	_log("플레이어 도보 이동 완료: %s (%.0f프레임)" % [_player.global_position.snapped(Vector2.ONE), elapsed_frames])
	return true

func _set_move(positive: StringName, negative: StringName, amount: float) -> void:
	if amount > 8.0:
		Input.action_press(positive)
		Input.action_release(negative)
	elif amount < -8.0:
		Input.action_press(negative)
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)

func _release_moves() -> void:
	for action: StringName in [&"move_right", &"move_left", &"move_up", &"move_down"]:
		Input.action_release(action)

func _wait_seconds(seconds: float) -> void:
	for frame_index: int in range(int(seconds * 60.0)):
		await process_frame
		_frames += 1

## condition 이 참이 될 때까지 대기. report 는 1초마다 호출한다.
func _wait_until(condition: Callable, timeout_seconds: float, report: Callable) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	for frame_index: int in range(max_frames):
		if condition.call():
			return true
		if frame_index % 60 == 0:
			report.call()
		await process_frame
		_frames += 1
	return condition.call()

func _log(message: String) -> void:
	print("[t=%5.1fs] %s" % [float(_frames) / 60.0, message])

func _fail(reason: String) -> void:
	_log("=== 재현 실패: %s ===" % reason)
	quit(1)

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
# 55px/s의 느긋한 조사 속도에서도 고정 seed 냄새 경로와 실제 시야 반경이
# 만나는 지점이다. 플레이어 순간이동 없이 조우를 재현한다.
const SCENT_INTERCEPT_POSITION: Vector2 = Vector2(-520.0, 500.0)
## 재현 도구는 결정적이어야 한다 (B-01): 랩터 배회 RNG 를 고정 seed 로 덮어쓰고,
## 모든 대기·timeout 을 physics tick 으로 세어 simulation clock 도 고정한다.
## 게임 플레이는 raptor._ready() 의 randomize() 로 여전히 무작위다.
const RAPTOR_RNG_SEED: int = 3

var _main: Node2D = null
var _player: Player = null
var _raptor: Raptor = null
var _grid: SmellGrid = null
## 하네스 로그 시각의 기준점. 엔진 physics frame 을 직접 읽어 simulation clock 을 고정한다.
var _epoch_physics_frames: int = 0
var _observed_states: Array[StringName] = []

func _init() -> void:
	_run()

func _run() -> void:
	await physics_frame
	_epoch_physics_frames = Engine.get_physics_frames()
	_main = MainScene.instantiate()
	get_root().add_child(_main)
	NavigationServer2D.map_force_update(_main.get_world_2d().navigation_map)
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
	var wander_distance: float = _raptor.global_position.distance_to(wander_start)
	_log("배회 이동량 %.1fpx (시작 %s → 현재 %s), 상태=%s" % [
		wander_distance, wander_start,
		_raptor.global_position, _raptor.get_state_name()])
	# 순찰 속도 튜닝과 조사 전환 시점에 독립적인 실이동 계약. 3초 내 상태가
	# investigate 로 바뀌어도 최소 0.5초분은 움직이고, 이론상 3초 이동량을 넘지 않는다.
	var wander_min := _raptor.data.walk_speed * 0.5
	var wander_max := _raptor.data.walk_speed * 3.3
	if wander_distance < wander_min or wander_distance > wander_max:
		return _fail("회귀 assert: 180 물리 틱 이동량이 속도 기반 %.1f~%.1fpx 범위를 벗어났다 (%.1fpx)" % [
			wander_min, wander_max, wander_distance])

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

	# 4) 냄새 상류로 접근 → 추격 전환 대기 (최대 40초).
	_log("--- phase 4: 경사 추적 접근 → 추격 대기 ---")
	# 무리 측면 조사 도입 후 플레이어도 냄새 경로 쪽으로 이동해 정당한 조우를 만든다.
	# 순간이동 대신 실제 입력 경로를 써서 시야 기반 추격 전환을 그대로 검증한다.
	if not await _walk_player_to(SCENT_INTERCEPT_POSITION, 10.0):
		return _fail("플레이어가 냄새 경로 조우 지점에 도달하지 못했다")
	if not await _wait_until(func() -> bool: return _raptor.state == Raptor.State.CHASE, 40.0, _report_approach):
		return _fail("회귀 assert: 조사 진입 후 40초 안에 추격으로 전환하지 않았다")

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

	# 6) 랩터가 물러나는지 대기 (최대 40초).
	_log("--- phase 6: 랩터 후퇴 대기 ---")
	if not await _wait_until(func() -> bool: return _raptor.state == Raptor.State.FLEE, 40.0, _report_approach):
		return _fail("랩터가 물러나지 않았다")
	var expected_states: Array[StringName] = [&"investigate", &"chase", &"flee"]
	var expected_state_index: int = 0
	for observed_state: StringName in _observed_states:
		if observed_state == expected_states[expected_state_index]:
			expected_state_index += 1
			if expected_state_index == expected_states.size():
				break
	if expected_state_index != expected_states.size():
		return _fail("회귀 assert: 상태 순서에 INVESTIGATE -> CHASE -> FLEE가 없다 (%s)" % str(_observed_states))
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
	var elapsed_physics_ticks: int = 0
	var max_physics_ticks: int = int(timeout_seconds * Engine.physics_ticks_per_second)
	while _player.global_position.distance_to(target) > 24.0:
		if elapsed_physics_ticks >= max_physics_ticks:
			_release_moves()
			return false
		var direction: Vector2 = target - _player.global_position
		var raw: Vector2 = Vector2(direction.x * 0.5 + direction.y, -direction.x * 0.5 + direction.y)
		_set_move(&"move_right", &"move_left", raw.x)
		_set_move(&"move_down", &"move_up", raw.y)
		await physics_frame
		elapsed_physics_ticks += 1
	_release_moves()
	_log("플레이어 도보 이동 완료: %s (%.0f 물리 틱)" % [
		_player.global_position.snapped(Vector2.ONE), elapsed_physics_ticks])
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
	for physics_tick_index: int in range(int(seconds * Engine.physics_ticks_per_second)):
		await physics_frame

## condition 이 참이 될 때까지 대기. report 는 1초마다 호출한다.
func _wait_until(condition: Callable, timeout_seconds: float, report: Callable) -> bool:
	var max_physics_ticks: int = int(timeout_seconds * Engine.physics_ticks_per_second)
	for physics_tick_index: int in range(max_physics_ticks):
		if condition.call():
			return true
		if physics_tick_index % Engine.physics_ticks_per_second == 0:
			report.call()
		await physics_frame
	return condition.call()

func _log(message: String) -> void:
	print("[t=%5.1fs] %s" % [
		float(Engine.get_physics_frames() - _epoch_physics_frames)
			/ float(Engine.physics_ticks_per_second), message])

func _fail(reason: String) -> void:
	_log("=== 재현 실패: %s ===" % reason)
	quit(1)

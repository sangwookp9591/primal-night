extends SceneTree

## 헤드리스 2인 테스트 하네스 (개발 빌드 전용, 게임 코드 아님).
## 실행: /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s scripts/net/two_player_harness.gd
##
## 한 프로세스에서 SceneTree.set_multiplayer 브랜치 2개(호스트 기계/클라이언트 기계)에
## 실제 main.tscn 을 각각 올리고 실제 ENet 루프백으로 검증한다:
##   2인 접속 → 아바타 스폰 → 각자 이동 → 서로의 위치 동기화 →
##   텔레포트 변조 거부(설계서 7.4) → 이탈 → 정리. 전 구간 자동 판정, 실패 시 종료 코드 1.
##
## 두 기계의 로컬 조작 아바타(호스트의 Player, 클라이언트의 자기 아바타)는
## Input 싱글턴을 공유하므로 같은 입력으로 동시에 움직인다 — 양방향 동기화를
## 한 번에 검증하는 데 그대로 쓴다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const RAPTOR_RNG_SEED: int = 3
const WALK_FRAMES: int = 72
const SETTLE_FRAMES: int = 90
const SYNC_TOLERANCE_PX: float = 8.0
const MIN_WALK_DISTANCE_PX: float = 80.0

var _frames: int = 0
var _host_left_observed: Array[StringName] = []


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	# 0) 두 '기계' 구성 — 브랜치마다 독립 MultiplayerAPI + 실제 main.tscn.
	_log("--- phase 0: 호스트/클라이언트 기계에 main.tscn 로드 ---")
	var host_root: Node = _make_machine("HostMachine")
	var client_root: Node = _make_machine("ClientMachine")
	var host_main: Node2D = host_root.get_node("Main")
	var client_main: Node2D = client_root.get_node("Main")

	for required: String in ["NetSession", "NetMovement", "Players", "Player"]:
		if host_main.get_node_or_null(required) == null:
			return _fail("main.tscn 에 %s 노드가 없다 — 네트워크가 게임 씬에 연결되지 않았다" % required)
	var host_session: SessionService = host_main.get_node("NetSession")
	var client_session: SessionService = client_main.get_node("NetSession")
	var host_net: NetMovement = host_main.get_node("NetMovement")
	var host_player: Player = host_main.get_node("Player")
	var client_view_of_host: Player = client_main.get_node("Player")
	_log("main.tscn 2개 로드 완료. NetSession/NetMovement/Players 연결 확인")

	host_session.player_left.connect(func(id: StringName) -> void: _host_left_observed.append(id))

	# 1) 접속.
	_log("--- phase 1: 호스트 개설 + 클라이언트 참가 ---")
	var error: Error = host_session.host_session()
	if error != OK:
		return _fail("host_session 실패: %d" % error)
	error = client_session.join_session("127.0.0.1:%d" % host_net.config.port)
	if error != OK:
		return _fail("join_session 실패: %d" % error)

	var client_id: StringName = &""
	if not await _wait_until(func() -> bool:
			return host_session.get_players().size() == 2, 10.0):
		return _fail("호스트가 참가를 관측하지 못했다")
	client_id = client_session.get_local_player_id()
	_log("접속 완료. host players=%s / client players=%s / client_id=%s" % [
		host_session.get_players(), client_session.get_players(), client_id])
	if client_session.get_players() != host_session.get_players():
		return _fail("양쪽 참가자 목록이 다르다")

	# 2) 아바타 스폰 (호스트 권위).
	_log("--- phase 2: 클라이언트 아바타 스폰 대기 ---")
	var avatar_path: NodePath = NodePath("Players/%s" % client_id)
	if not await _wait_until(func() -> bool:
			return host_main.has_node(avatar_path) and client_main.has_node(avatar_path), 10.0):
		return _fail("아바타가 양쪽에 스폰되지 않았다")
	var host_view_of_client: Player = host_main.get_node(avatar_path)
	var client_avatar: Player = client_main.get_node(avatar_path)
	_log("스폰 완료. host측=%s client측=%s" % [
		host_view_of_client.global_position.snapped(Vector2.ONE),
		client_avatar.global_position.snapped(Vector2.ONE)])

	# 3) 각자 이동 (공유 Input — 두 기계의 로컬 아바타가 동시에 걷는다).
	_log("--- phase 3: 이동 %d프레임 (move_right) ---" % WALK_FRAMES)
	var host_start: Vector2 = host_player.global_position
	var client_start: Vector2 = client_avatar.global_position
	Input.action_press(&"move_right")
	for i: int in range(WALK_FRAMES):
		await physics_frame
		_frames += 1
	Input.action_release(&"move_right")
	for i: int in range(SETTLE_FRAMES):
		await physics_frame
		_frames += 1

	var host_moved: float = host_player.global_position.distance_to(host_start)
	var client_moved: float = client_avatar.global_position.distance_to(client_start)
	_log("이동량: 호스트 %.0fpx / 클라이언트 %.0fpx" % [host_moved, client_moved])
	if host_moved < MIN_WALK_DISTANCE_PX:
		return _fail("호스트 플레이어가 충분히 이동하지 않았다 (%.0fpx)" % host_moved)
	if client_moved < MIN_WALK_DISTANCE_PX:
		return _fail("클라이언트 아바타가 충분히 이동하지 않았다 (%.0fpx)" % client_moved)

	# 4) 상호 위치 동기화 판정.
	_log("--- phase 4: 위치 동기화 판정 ---")
	var host_sync_error: float = client_view_of_host.global_position.distance_to(host_player.global_position)
	var client_sync_error: float = host_view_of_client.global_position.distance_to(client_avatar.global_position)
	_log("동기화 오차: 호스트→클라 %.1fpx / 클라→호스트 %.1fpx (허용 %.0fpx)" % [
		host_sync_error, client_sync_error, SYNC_TOLERANCE_PX])
	if host_sync_error > SYNC_TOLERANCE_PX:
		return _fail("호스트 위치가 클라이언트로 동기화되지 않았다")
	if client_sync_error > SYNC_TOLERANCE_PX:
		return _fail("클라이언트 위치가 호스트로 동기화되지 않았다")
	if host_net.get_move_violation_count(client_id) != 0:
		return _fail("정직한 이동인데 위반이 기록되었다")

	# 5) 텔레포트 변조 거부 (설계서 7.4: 좌표를 그대로 신뢰하지 않음).
	_log("--- phase 5: 텔레포트 변조 주장 → 호스트 거부 + 보정 ---")
	var before_cheat: Vector2 = host_view_of_client.global_position
	client_avatar.global_position = before_cheat + Vector2(5000.0, 0.0)
	for i: int in range(30):
		await physics_frame
		_frames += 1
	var cheat_result: float = host_view_of_client.global_position.distance_to(before_cheat)
	var violations: int = host_net.get_move_violation_count(client_id)
	_log("호스트측 아바타 이탈량 %.0fpx, 위반 기록 %d건" % [cheat_result, violations])
	if cheat_result > 100.0:
		return _fail("호스트가 텔레포트 주장을 수용했다 (%.0fpx)" % cheat_result)
	if violations == 0:
		return _fail("텔레포트 위반이 기록되지 않았다")
	if not await _wait_until(func() -> bool:
			return client_avatar.global_position.distance_to(before_cheat) < 100.0, 5.0):
		return _fail("보정 스냅샷이 변조 위치를 되돌리지 못했다")
	_log("보정 완료: 클라이언트 아바타 %s (기준 %s)" % [
		client_avatar.global_position.snapped(Vector2.ONE), before_cheat.snapped(Vector2.ONE)])

	# 6) 이탈 → 정리.
	_log("--- phase 6: 클라이언트 이탈 ---")
	client_session.leave_session()
	if not await _wait_until(func() -> bool:
			return not host_main.has_node(avatar_path) and not client_main.has_node(avatar_path) \
				and _host_left_observed.has(client_id), 10.0):
		return _fail("이탈 후 정리가 완료되지 않았다 (host_left=%s)" % str(_host_left_observed))
	if host_session.get_players() != ([&"1"] as Array[StringName]):
		return _fail("이탈 후 호스트 참가자 목록이 [1] 이 아니다: %s" % str(host_session.get_players()))
	_log("이탈 정리 완료. host players=%s" % [host_session.get_players()])

	_log("=== 2인 하네스 성공: 접속·스폰·이동 동기화·변조 거부·이탈 정리 ===")
	quit(0)


## 브랜치 루트 + 독립 MultiplayerAPI + main.tscn 인스턴스로 '기계' 하나를 만든다.
func _make_machine(machine_name: String) -> Node:
	var root: Node = Node.new()
	root.name = machine_name
	get_root().add_child(root)
	set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var main: Node2D = MainScene.instantiate()
	main.name = "Main"
	root.add_child(main)
	# 랩터 배회 RNG 고정 — 이 하네스 판정과 무관하지만 로그 재현성을 위해 (B-01 관례).
	var raptor: Raptor = main.get_node("Raptor")
	raptor.rng.seed = RAPTOR_RNG_SEED
	return root


func _wait_until(condition: Callable, timeout_seconds: float, report: Callable = Callable()) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	for frame_index: int in range(max_frames):
		if condition.call():
			return true
		if report.is_valid() and frame_index % 60 == 0:
			report.call()
		await physics_frame
		_frames += 1
	return condition.call()


func _log(message: String) -> void:
	print("[t=%5.1fs] %s" % [float(_frames) / 60.0, message])


func _fail(reason: String) -> void:
	_log("=== 2인 하네스 실패: %s ===" % reason)
	quit(1)

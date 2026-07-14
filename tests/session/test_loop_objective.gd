extends GutTest

## LoopObjective — 회색 상자 감지 루프의 세션 판정 (계획서 W3-T2, 설계서 4.x).
## 루프: 위험 노출(출혈·냄새) → 랩터 회피 → 지정 지점 도달.
## 불변식:
##   1. phase 시간이 다 되면 세션 실패다.
##   2. 위험에 노출된 뒤 지정 지점에 닿으면 세션 성공이다.
##   3. 노출 없이 지점만 밟는 것은 이 루프가 아니다 — 판정은 PENDING 으로 남는다.
##   4. 시간·판정의 권위는 호스트다. 클라이언트에는 "도달했다"를 주장할 RPC 가 없고,
##      참가·재접속 시 호스트 스냅샷으로 세션 상태를 복원받는다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const PORT: int = 8921
const PHASE_SECONDS: float = 900.0
const EXTRACTION: Vector2 = Vector2(600.0, 400.0)

var _sides: Array[Dictionary] = []


func after_each() -> void:
	for side: Dictionary in _sides:
		(side.session as SessionService).leave_session()
		get_tree().set_multiplayer(null, (side.root as Node).get_path())
	_sides.clear()


## 한쪽 '기계': 세션 + 아바타 + NetMovement + SessionClock + LoopObjective.
## (tests/net/test_net_resync.gd 의 2브랜치 관례 — 호스트/클라이언트를 한 프로세스에서 돌린다.)
func _make_side(side_name: String) -> Dictionary:
	var root: Node = add_child_autofree(Node.new())
	root.name = side_name
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())

	var session: LocalSessionService = LocalSessionService.new()
	session.name = "NetSession"
	session.config = NetConfig.new()
	session.config.port = PORT
	root.add_child(session)

	var host_player: Player = PlayerScene.instantiate()
	host_player.name = "Player"
	root.add_child(host_player)

	var container: Node2D = Node2D.new()
	container.name = "Players"
	root.add_child(container)

	var net_move: NetMovement = NetMovement.new()
	net_move.name = "NetMovement"
	net_move.session_path = ^"../NetSession"
	net_move.host_player_path = ^"../Player"
	net_move.players_container_path = ^"../Players"
	net_move.avatar_scene = PlayerScene
	net_move.config = session.config
	root.add_child(net_move)

	var clock: SessionClock = SessionClock.new()
	clock.name = "SessionClock"
	clock.phase_duration_seconds = PHASE_SECONDS
	root.add_child(clock)

	var objective: LoopObjective = LoopObjective.new()
	objective.name = "LoopObjective"
	objective.position = EXTRACTION
	objective.clock_path = ^"../SessionClock"
	objective.session_path = ^"../NetSession"
	objective.host_player_path = ^"../Player"
	objective.players_container_path = ^"../Players"
	root.add_child(objective)

	var side: Dictionary = {
		root = root, session = session, host_player = host_player,
		container = container, net_move = net_move, clock = clock, objective = objective,
	}
	_sides.append(side)
	return side


func test_phase_time_expiry_fails_the_session() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective: LoopObjective = side.objective
	objective.mark_risk_exposed()

	(side.clock as SessionClock).advance(PHASE_SECONDS + 1.0)
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.FAILED,
		"phase 시간이 다 되면 지점에 못 갔으니 세션 실패다")


## 성공 판정은 '노출 뒤 도달'만 인정한다. 지점만 밟는 것은 이 루프가 아니다.
func test_reaching_extraction_succeeds_only_after_risk_exposure() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective: LoopObjective = side.objective
	(side.host_player as Player).global_position = EXTRACTION
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.PENDING,
		"위험에 노출된 적이 없으면 지점을 밟아도 루프 성공이 아니다")

	objective.mark_risk_exposed()
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.SUCCEEDED,
		"위험에 노출된 뒤 지정 지점에 닿으면 세션 성공이다")
	assert_false((side.clock as SessionClock).running, "판정이 끝나면 시계도 멈춘다")


## 출혈은 피 냄새를 만들어 랩터를 부른다 = 위험 노출이다 (설계서 5.2/5.4).
func test_bleeding_marks_risk_exposure() -> void:
	var side: Dictionary = _make_side("Solo")
	(side.host_player as Player).health.start_bleeding()
	await wait_physics_frames(2)

	assert_true((side.objective as LoopObjective).risk_exposed,
		"출혈은 위험 노출로 기록된다")


func test_smelly_item_pickup_marks_risk_exposure() -> void:
	var side: Dictionary = _make_side("Solo")

	get_node("/root/EventBus").item_picked_up.emit(&"raw_meat", side.host_player)
	await wait_physics_frames(1)

	assert_true((side.objective as LoopObjective).risk_exposed,
		"냄새 원천 아이템 보유는 위험 노출로 기록된다")


func test_bait_smell_marks_risk_exposure() -> void:
	var side: Dictionary = _make_side("Solo")

	get_node("/root/EventBus").smell_emitted.emit(Vector2(100.0, 100.0), 55.0, &"bait")
	await wait_physics_frames(1)

	assert_true((side.objective as LoopObjective).risk_exposed,
		"미끼가 만든 냄새는 위험 노출로 기록된다")


## 참가·재접속한 클라이언트는 호스트의 세션 시간·노출·판정을 스냅샷으로 되찾는다.
## 클라이언트 시계는 혼자 900초에서 흐르므로, 호스트 값과 맞다는 것은 스냅샷이
## 도착했다는 뜻이다 (뮤테이션 자가검증: 스냅샷을 빼면 이 검증이 잡는다).
func test_reconnected_client_restores_session_state_from_host() -> void:
	var host: Dictionary = _make_side("HostSide")
	var client: Dictionary = _make_side("ClientSide")
	var host_clock: SessionClock = host.clock
	var client_clock: SessionClock = client.clock
	var host_objective: LoopObjective = host.objective
	var client_objective: LoopObjective = client.objective

	host_clock.advance(300.0)
	assert_eq((host.session as LocalSessionService).host_session(), OK)
	assert_eq((client.session as LocalSessionService).join_session("127.0.0.1:%d" % PORT), OK)
	await wait_for_signal((host.session as SessionService).player_joined, 5.0, "호스트가 참가를 관측해야 한다")
	var client_id: StringName = (client.session as SessionService).get_local_player_id()

	assert_true(await wait_until(func() -> bool:
		return absf(client_clock.remaining_seconds - host_clock.remaining_seconds) < 5.0, 5.0),
		"참가한 클라이언트는 호스트의 남은 phase 시간을 받아야 한다")

	# 접속 중에 세션이 더 진행된다: 시간이 흐르고 플레이어가 위험에 노출된다.
	host_clock.advance(200.0)
	host_objective.mark_risk_exposed()

	(client.session as SessionService).leave_session()
	assert_true(await wait_until(func() -> bool:
		return (host.session as SessionService).get_players().size() == 1, 5.0),
		"호스트가 이탈을 관측해야 한다")

	assert_eq((client.session as LocalSessionService).join_session({
		address = "127.0.0.1", port = PORT, player_id = client_id,
	}), OK, "재참가가 시작되어야 한다")
	await wait_for_signal((host.session as SessionService).player_reconnected, 5.0, "재접속으로 관측되어야 한다")

	assert_true(await wait_until(func() -> bool:
		return absf(client_clock.remaining_seconds - host_clock.remaining_seconds) < 5.0, 5.0),
		"재접속한 클라이언트는 호스트의 남은 phase 시간을 되찾아야 한다")
	assert_true(client_objective.risk_exposed,
		"재접속한 클라이언트는 위험 노출 상태를 되찾아야 한다")
	assert_eq(client_objective.outcome, host_objective.outcome,
		"세션 판정은 호스트 값 그대로다")


## 가짜 완료 금지 (설계서 15장): 세션 골격이 실제 게임 씬에 있어야 한다.
func test_main_scene_runs_the_loop_session() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(3)
	var clock: SessionClock = main.get_node_or_null("SessionClock") as SessionClock
	var objective: LoopObjective = main.get_node_or_null("LoopObjective") as LoopObjective

	assert_not_null(clock, "세션 시계가 실제 게임 씬에 있어야 한다")
	assert_not_null(objective, "루프 목표가 실제 게임 씬에 있어야 한다")
	assert_between(clock.phase_duration_seconds, 600.0, 900.0, "10~15분짜리 루프다")

	var player: Player = main.get_node("Player")
	assert_gt(objective.global_position.distance_to(player.global_position), 500.0,
		"지정 지점은 스폰에서 걸어가야 할 만큼 떨어져 있어야 한다")

	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = objective.global_position
	query.collision_mask = 1
	assert_true(objective.get_world_2d().direct_space_state.intersect_point(query).is_empty(),
		"지정 지점이 벽 안이면 루프를 완주할 수 없다")

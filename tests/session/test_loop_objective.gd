extends GutTest

## LoopObjective — 회색 상자 감지 루프의 세션 판정 (계획서 W3-T2/W5-T2, 설계서 4.x).
## 루프: 플레이어 기원 위험 노출 → (그 이후) 랩터 조사/추격 관측 → 실제 회피(FLEE·관심 상실)
##       → 지정 지점 도달 = 성공. 랩터가 포획 반경 안에 유예 이상 머물면 실패. 시간 만료도 실패.
## 불변식:
##   1. 월드 배경 냄새(바닥 raw_meat 주기 발신)만으로는 노출되지 않는다.
##   2. 플레이어 출혈·날고기 획득·호스트 확정 미끼 투척은 각각 노출이다.
##   3. 노출 뒤 지점만 밟는 것으로는 성공이 아니다 — 랩터 관측·회피가 순서에 있어야 한다.
##   4. 노출 전 랩터 전환은 성공 순서에 재사용되지 않는다.
##   5. 짧은 근접은 허용하되 포획 유예 초과는 실패다. 결과 확정 뒤 시계는 멈춘다.
##   6. 시간·판정의 권위는 호스트다. 참가·재접속 시 호스트 스냅샷으로 복원받는다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const RaptorScript = preload("res://scripts/creature/raptor.gd")
const PORT: int = 8921
const PHASE_SECONDS: float = 900.0
const EXTRACTION: Vector2 = Vector2(600.0, 400.0)
## 시퀀스 테스트에서 포획이 끼어들지 않도록 랩터를 멀리 둔다.
const RAPTOR_FAR: Vector2 = Vector2(10000.0, 10000.0)

var _sides: Array[Dictionary] = []


func after_each() -> void:
	for side: Dictionary in _sides:
		(side.session as SessionService).leave_session()
		get_tree().set_multiplayer(null, (side.root as Node).get_path())
	_sides.clear()


## 한쪽 '기계': 세션 + 아바타 + NetMovement + (선택)Raptor/(선택)NetPickup + SessionClock + LoopObjective.
## (tests/net/test_net_resync.gd 의 2브랜치 관례 — 호스트/클라이언트를 한 프로세스에서 돌린다.)
## ★ Raptor/NetPickup 은 LoopObjective 보다 먼저 트리에 넣어야 _ready 의 신호 연결이 성립한다.
func _make_side(side_name: String, with_raptor: bool = false, with_pickup: bool = false) -> Dictionary:
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

	var raptor: Raptor = null
	if with_raptor:
		raptor = RaptorScript.new()
		raptor.name = "Raptor"
		raptor.set_physics_process(false)  # AI 정지 — 상태는 테스트가 직접 emit 한다.
		root.add_child(raptor)
		raptor.global_position = RAPTOR_FAR

	var net_pickup: NetPickup = null
	if with_pickup:
		net_pickup = NetPickup.new()
		net_pickup.name = "NetPickup"
		root.add_child(net_pickup)

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
		raptor = raptor, net_pickup = net_pickup,
	}
	_sides.append(side)
	return side


## ── 노출 판정: 출처를 구분한다 (W5-T2) ──────────────────────────────────────────

## ★ 월드 배경 냄새는 노출이 아니다 (디버그 판 바닥 raw_meat 가 먼저 방출해도 목표가 안 열린다).
func test_world_smell_alone_does_not_mark_exposure() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective: LoopObjective = side.objective

	get_node("/root/EventBus").smell_emitted.emit(Vector2(100.0, 100.0), 45.0, &"raw_meat")
	get_node("/root/EventBus").smell_emitted.emit(Vector2(100.0, 100.0), 55.0, &"bait")
	await wait_physics_frames(2)

	assert_false(objective.risk_exposed,
		"출처 없는 월드 냄새만으로는 위험 노출이 아니다 (배경 냄새와 플레이어 기원 구분)")


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
		"냄새 원천 아이템(날고기) 획득은 위험 노출로 기록된다")


## ★ 호스트가 확정한 미끼 투척만 노출이다 (NetPickup 이 직접 신호로 알린다).
func test_host_confirmed_bait_throw_marks_risk_exposure() -> void:
	var side: Dictionary = _make_side("Solo", false, true)
	var objective: LoopObjective = side.objective
	var host_player: Player = side.host_player
	var net_pickup: NetPickup = side.net_pickup

	host_player.inventory.add_item(&"bait", 1)
	net_pickup.request_throw_bait_for(host_player, host_player.global_position + Vector2(50.0, 0.0))
	await wait_physics_frames(1)

	assert_true(objective.risk_exposed,
		"호스트가 확정한 미끼 투척은 위험 노출로 기록된다")


## ── 성공 순서: 노출 → 관측 → 회피 → 탈출 ────────────────────────────────────────

## 노출 뒤 바로 탈출 지점을 밟아도 성공이 아니다 — 랩터 관측·회피가 순서에 있어야 한다.
func test_exposure_then_extraction_alone_does_not_succeed() -> void:
	var side: Dictionary = _make_side("Solo", true)
	var objective: LoopObjective = side.objective

	objective.mark_risk_exposed()
	(side.host_player as Player).global_position = EXTRACTION
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.PENDING,
		"랩터 조사/추격·회피를 관측하지 않으면 노출 후 지점을 밟아도 성공이 아니다")


## 노출 → 조사/추격 관측 → 회피(관심 상실) → 탈출 = 성공. 시계도 멈춘다.
func test_full_sequence_succeeds_and_stops_the_clock() -> void:
	var side: Dictionary = _make_side("Solo", true)
	var objective: LoopObjective = side.objective
	var raptor: Raptor = side.raptor

	objective.mark_risk_exposed()
	(side.host_player as Player).global_position = EXTRACTION
	# 노출 이후 조사 진입 → 관심 상실(배회 복귀)로 회피.
	raptor.state_changed.emit(Raptor.State.WANDER, Raptor.State.INVESTIGATE)
	raptor.state_changed.emit(Raptor.State.INVESTIGATE, Raptor.State.WANDER)
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.SUCCEEDED,
		"노출→관측→회피→탈출 순서를 채우면 성공이다")
	assert_false((side.clock as SessionClock).running, "판정이 끝나면 시계도 멈춘다")


## FLEE(불 보호 도주)도 회피로 인정한다.
func test_flee_counts_as_evasion() -> void:
	var side: Dictionary = _make_side("Solo", true)
	var objective: LoopObjective = side.objective
	var raptor: Raptor = side.raptor

	objective.mark_risk_exposed()
	(side.host_player as Player).global_position = EXTRACTION
	raptor.state_changed.emit(Raptor.State.INVESTIGATE, Raptor.State.CHASE)
	raptor.state_changed.emit(Raptor.State.CHASE, Raptor.State.FLEE)
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.SUCCEEDED,
		"추격 뒤 도주(FLEE) 관측도 회피로 인정된다")


## ★ 노출 전의 랩터 전환은 성공 순서에 재사용되지 않는다.
func test_pre_exposure_raptor_transitions_are_not_reused() -> void:
	var side: Dictionary = _make_side("Solo", true)
	var objective: LoopObjective = side.objective
	var raptor: Raptor = side.raptor

	# 노출 전에 조사·회피가 일어나도 순서에 반영되지 않는다.
	raptor.state_changed.emit(Raptor.State.WANDER, Raptor.State.INVESTIGATE)
	raptor.state_changed.emit(Raptor.State.INVESTIGATE, Raptor.State.WANDER)

	objective.mark_risk_exposed()
	(side.host_player as Player).global_position = EXTRACTION
	await wait_physics_frames(8)
	assert_eq(objective.outcome, LoopObjective.Outcome.PENDING,
		"노출 전 랩터 전환은 재사용되지 않으므로 아직 성공이 아니다")

	# 노출 이후 다시 관측·회피하면 성공한다.
	raptor.state_changed.emit(Raptor.State.WANDER, Raptor.State.INVESTIGATE)
	raptor.state_changed.emit(Raptor.State.INVESTIGATE, Raptor.State.WANDER)
	await wait_physics_frames(8)
	assert_eq(objective.outcome, LoopObjective.Outcome.SUCCEEDED,
		"노출 이후 관측·회피를 새로 채우면 성공이다")


## ── 포획 실패 ─────────────────────────────────────────────────────────────────

func test_capture_grace_exceeded_fails_the_session() -> void:
	var side: Dictionary = _make_side("Solo", true)
	var objective: LoopObjective = side.objective
	objective.capture_radius = 100.0
	objective.capture_grace_seconds = 0.01

	# 랩터를 아바타 바로 옆에 둔다 (기본 위치 0,0 근처).
	(side.host_player as Player).global_position = Vector2.ZERO
	(side.raptor as Raptor).global_position = Vector2(30.0, 0.0)
	await wait_physics_frames(10)

	assert_eq(objective.outcome, LoopObjective.Outcome.FAILED,
		"랩터가 포획 반경 안에 유예 이상 머물면 세션 실패다")
	assert_false((side.clock as SessionClock).running, "실패 확정 뒤 시계는 멈춘다")


func test_brief_proximity_within_grace_does_not_fail() -> void:
	var side: Dictionary = _make_side("Solo", true)
	var objective: LoopObjective = side.objective
	objective.capture_radius = 100.0
	objective.capture_grace_seconds = 2.0

	(side.host_player as Player).global_position = Vector2.ZERO
	(side.raptor as Raptor).global_position = Vector2(30.0, 0.0)
	await wait_physics_frames(3)  # 유예보다 훨씬 짧게만 근접.
	(side.raptor as Raptor).global_position = RAPTOR_FAR
	await wait_physics_frames(6)

	assert_eq(objective.outcome, LoopObjective.Outcome.PENDING,
		"유예 안의 짧은 근접은 실패가 아니다")


## ── 시간 만료 / 재접속 (기존 계약 유지) ───────────────────────────────────────

func test_phase_time_expiry_fails_the_session() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective: LoopObjective = side.objective
	objective.mark_risk_exposed()

	(side.clock as SessionClock).advance(PHASE_SECONDS + 1.0)
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.FAILED,
		"phase 시간이 다 되면 지점에 못 갔으니 세션 실패다")


## 참가·재접속한 클라이언트는 호스트의 세션 시간·노출·판정을 스냅샷으로 되찾는다.
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

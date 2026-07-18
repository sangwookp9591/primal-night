extends GutTest

## LoopObjective — 회색 상자 감지 루프의 세션 판정 (계획서 W3-T2, 설계서 4.x).
## 루프: 위험 노출(출혈·냄새) → 랩터 회피 → 지정 지점 도달.
## 불변식:
##   1. 3일째 시간이 다 되면 생존자는 다음 순환에 잔류한다.
##   2. 위험에 노출된 뒤 지정 지점에 닿으면 관리 상태에 따라 탈출 결과가 갈린다.
##   3. 노출 없이 지점만 밟는 것은 이 루프가 아니다 — 판정은 PENDING 으로 남는다.
##   4. 시간·판정의 권위는 호스트다. 클라이언트에는 "도달했다"를 주장할 RPC 가 없고,
##      참가·재접속 시 호스트 스냅샷으로 세션 상태를 복원받는다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const PORT: int = 8926
const DAY_SECONDS: float = 10.0
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

	var base: Node2D = Node2D.new()
	base.name = "Base"
	base.position = Vector2(120.0, 80.0)
	root.add_child(base)

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
	clock.daylight_duration_seconds = 7.0
	clock.dusk_duration_seconds = 1.0
	clock.night_duration_seconds = 2.0
	clock.total_days = 3
	root.add_child(clock)

	var objective: LoopObjective = LoopObjective.new()
	objective.name = "LoopObjective"
	objective.position = EXTRACTION
	objective.clock_path = ^"../SessionClock"
	objective.session_path = ^"../NetSession"
	objective.host_player_path = ^"../Player"
	objective.players_container_path = ^"../Players"
	objective.base_camp_path = ^"../Base"
	root.add_child(objective)

	var side: Dictionary = {
		root = root, session = session, host_player = host_player,
		container = container, base = base, net_move = net_move, clock = clock, objective = objective,
	}
	_sides.append(side)
	return side


func test_final_day_time_expiry_remains_when_someone_is_alive() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective: LoopObjective = side.objective
	objective.mark_risk_exposed()

	(side.clock as SessionClock).advance(DAY_SECONDS * 3.0 + 1.0)
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.REMAIN,
		"3일째 시간이 다 되어도 생존 중이면 다음 순환에 잔류한다")


## 성공 판정은 '노출 뒤 도달'만 인정한다. 지점만 밟는 것은 이 루프가 아니다.
func test_reaching_extraction_forces_escape_when_risk_was_not_managed() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective: LoopObjective = side.objective
	(side.host_player as Player).global_position = EXTRACTION
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.PENDING,
		"위험에 노출된 적이 없으면 지점을 밟아도 루프 성공이 아니다")

	objective.mark_risk_exposed()
	(side.clock as SessionClock).advance(DAY_SECONDS * 2.0)
	await wait_physics_frames(8)

	assert_eq(objective.outcome, LoopObjective.Outcome.FORCED_ESCAPE,
		"관리 이력이 없는 위험 노출 뒤 도달은 강제 탈출이다")
	assert_false((side.clock as SessionClock).running, "판정이 끝나면 시계도 멈춘다")


func test_treated_bleeding_and_maintained_fire_produce_stable_escape() -> void:
	var side: Dictionary = _make_side("Solo")
	var player: Player = side.host_player
	player.health.start_bleeding()
	player.health.stop_bleeding()
	get_node("/root/EventBus").campfire_lit.emit(side.root, Vector2.ZERO, 100.0)
	player.global_position = EXTRACTION
	await wait_physics_frames(8)

	assert_eq((side.objective as LoopObjective).outcome, LoopObjective.Outcome.STABLE_ESCAPE)
	assert_true((side.objective as LoopObjective).narrative_text().contains("무사히"))


func test_active_bleeding_produces_forced_escape() -> void:
	var side: Dictionary = _make_side("Solo")
	(side.host_player as Player).health.start_bleeding()
	(side.host_player as Player).global_position = EXTRACTION
	await wait_physics_frames(8)

	assert_eq((side.objective as LoopObjective).outcome, LoopObjective.Outcome.FORCED_ESCAPE)
	assert_true((side.objective as LoopObjective).narrative_text().contains("대가"))


func test_rift_and_body_signals_mirror_escape_readiness_without_changing_outcome() -> void:
	var side: Dictionary = _make_side("Solo")
	var player := side.host_player as Player
	var objective := side.objective as LoopObjective
	player.global_position = EXTRACTION + Vector2(120.0, 0.0)
	player.health.start_bleeding()
	await wait_physics_frames(2)

	assert_eq(objective.expected_rift_signal(), LoopObjective.RiftSignal.UNSTABLE)
	assert_eq(objective.rift_signal, LoopObjective.RiftSignal.UNSTABLE)
	assert_eq(objective.body_signal, LoopObjective.BodySignal.GUARDED)
	assert_eq(objective.outcome, LoopObjective.Outcome.PENDING,
		"접근 표현은 판정을 앞당기지 않는다")

	player.health.stop_bleeding()
	get_node("/root/EventBus").campfire_lit.emit(side.root, Vector2.ZERO, 100.0)
	await wait_physics_frames(2)

	assert_eq(objective._escape_outcome(), LoopObjective.Outcome.STABLE_ESCAPE)
	assert_eq(objective.expected_rift_signal(), LoopObjective.RiftSignal.CALM)
	assert_eq(objective.rift_signal, LoopObjective.RiftSignal.CALM)
	assert_eq(objective.body_signal, LoopObjective.BodySignal.STEADY_BREATH)


func test_final_night_near_base_emits_world_narration_once() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective := side.objective as LoopObjective
	var player := side.host_player as Player
	player.global_position = (side.base as Node2D).global_position
	watch_signals(objective)

	(side.clock as SessionClock).advance(DAY_SECONDS * 2.0 + 8.1)
	await wait_physics_frames(2)

	assert_signal_emit_count(objective, "environmental_narration", 1)
	assert_eq(objective.last_environmental_narration, LoopObjective.FINAL_NIGHT_TEXT)
	assert_true((objective.get_node("FinalNightWorldNarration") as Label).visible,
		"서술은 HUD가 아니라 거점 위 월드 Label로 보인다")
	objective._on_clock_phase_changed(SessionClock.Phase.NIGHT)
	assert_signal_emit_count(objective, "environmental_narration", 1,
		"마지막 밤 서술은 한 번만 난다")


func test_result_summaries_name_each_outcome_cause_and_forced_cost() -> void:
	var objective := (_make_side("Solo").objective as LoopObjective)
	objective.record_cause_event(&"lure")
	objective.outcome = LoopObjective.Outcome.STABLE_ESCAPE
	assert_true(objective.narrative_text().contains("남긴 위험은 없었다"))
	objective.outcome = LoopObjective.Outcome.FORCED_ESCAPE
	assert_true(objective.narrative_text().contains("장비") \
		and objective.narrative_text().contains("남긴 위험") \
		and objective.narrative_text().contains("고기 냄새"))
	objective.outcome = LoopObjective.Outcome.REMAIN
	assert_true(objective.narrative_text().contains("불을 지켜") \
		and objective.narrative_text().contains("떠나지 않고"))
	objective.outcome = LoopObjective.Outcome.FAILED
	assert_true(objective.narrative_text().contains("고기 냄새"),
		"실패도 기존 사망 원인 문장 체계를 재사용한다")


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


func test_cause_history_is_bounded_and_keeps_latest_event() -> void:
	var side: Dictionary = _make_side("Solo")
	var objective := side.objective as LoopObjective
	for index: int in range(LoopObjective.CAUSE_HISTORY_CAPACITY + 4):
		objective.record_cause_event(&"noise" if index < LoopObjective.CAUSE_HISTORY_CAPACITY + 3 else &"blood")

	assert_eq(objective.cause_history.size(), LoopObjective.CAUSE_HISTORY_CAPACITY)
	assert_eq(objective.latest_cause_kind(), &"blood")


func test_death_cause_templates_cover_sense_and_context_combinations() -> void:
	var objective := (_make_side("Solo").objective as LoopObjective)
	var blood_wind := objective.compose_death_cause(&"blood", Raptor.State.INVESTIGATE, Vector2.LEFT)
	var blood_still := objective.compose_death_cause(&"blood", Raptor.State.INVESTIGATE, Vector2.ZERO)
	var noise_chase := objective.compose_death_cause(&"noise", Raptor.State.CHASE, Vector2.ZERO)
	var noise_search := objective.compose_death_cause(&"noise", Raptor.State.INVESTIGATE, Vector2.ZERO)
	var lure_wind := objective.compose_death_cause(&"lure", Raptor.State.INVESTIGATE, Vector2.DOWN)
	var lure_still := objective.compose_death_cause(&"lure", Raptor.State.INVESTIGATE, Vector2.ZERO)
	var sight_chase := objective.compose_death_cause(&"sight", Raptor.State.CHASE, Vector2.ZERO)
	var sight_patrol := objective.compose_death_cause(&"sight", Raptor.State.WANDER, Vector2.ZERO)
	var poison := objective.compose_death_cause(&"poison")
	var food_poison := objective.compose_death_cause(&"food_poison")

	assert_true(blood_wind.contains("피 냄새") and blood_wind.contains("풍"))
	assert_true(blood_still.contains("발밑"))
	assert_true(noise_chase.contains("발소리") and noise_chase.contains("추격"))
	assert_true(noise_search.contains("소음") and noise_search.contains("위치"))
	assert_true(lure_wind.contains("유인 냄새") and lure_wind.contains("풍"))
	assert_true(lure_still.contains("고기 냄새"))
	assert_true(sight_chase.contains("시야") and sight_chase.contains("추격"))
	assert_true(sight_patrol.contains("순찰선"))
	assert_true(poison.contains("독버섯"))
	assert_true(food_poison.contains("익히지 않은 고기"))


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

	host_clock.advance(12.0)
	assert_eq((host.session as LocalSessionService).host_session(), OK)
	assert_eq((client.session as LocalSessionService).join_session("127.0.0.1:%d" % PORT), OK)
	await wait_for_signal((host.session as SessionService).player_joined, 5.0, "호스트가 참가를 관측해야 한다")
	var client_id: StringName = (client.session as SessionService).get_local_player_id()

	assert_true(await wait_until(func() -> bool:
		return client_clock.current_day == host_clock.current_day \
			and absf(client_clock.time_of_day_seconds - host_clock.time_of_day_seconds) < 1.0, 5.0),
		"참가한 클라이언트는 호스트의 day/time을 받아야 한다")

	# 접속 중에 세션이 더 진행된다: 시간이 흐르고 플레이어가 위험에 노출된다.
	host_clock.advance(5.0)
	(host.host_player as Player).health.start_bleeding()
	(host.host_player as Player).health.stop_bleeding()
	get_node("/root/EventBus").campfire_lit.emit(host.root, Vector2.ZERO, 100.0)
	(host.host_player as Player).global_position = EXTRACTION
	assert_true(await wait_until(func() -> bool:
		return host_objective.outcome == LoopObjective.Outcome.STABLE_ESCAPE, 3.0),
		"호스트가 안정 탈출 결과를 확정해야 한다")

	(client.session as SessionService).leave_session()
	assert_true(await wait_until(func() -> bool:
		return (host.session as SessionService).get_players().size() == 1, 5.0),
		"호스트가 이탈을 관측해야 한다")

	assert_eq((client.session as LocalSessionService).join_session({
		address = "127.0.0.1", port = PORT, player_id = client_id,
	}), OK, "재참가가 시작되어야 한다")
	await wait_for_signal((host.session as SessionService).player_reconnected, 5.0, "재접속으로 관측되어야 한다")

	assert_true(await wait_until(func() -> bool:
		return client_clock.current_day == host_clock.current_day \
			and absf(client_clock.time_of_day_seconds - host_clock.time_of_day_seconds) < 1.0, 5.0),
		"재접속한 클라이언트는 호스트의 day/time을 되찾아야 한다")
	assert_true(client_objective.risk_exposed,
		"재접속한 클라이언트는 위험 노출 상태를 되찾아야 한다")
	assert_eq(client_objective.outcome, host_objective.outcome,
		"세션 판정은 호스트 값 그대로다")
	assert_eq(client_objective.outcome, LoopObjective.Outcome.STABLE_ESCAPE,
		"늦게 다시 참가해도 확정된 서사 결과를 복원해야 한다")
	assert_eq(client_objective.narrative_text(), host_objective.narrative_text(),
		"결과 문장도 동일한 확정 결과에서 재현되어야 한다")


func test_client_cannot_claim_a_day() -> void:
	var host: Dictionary = _make_side("HostSide")
	var client: Dictionary = _make_side("ClientSide")
	assert_eq((host.session as LocalSessionService).host_session(), OK)
	assert_eq((client.session as LocalSessionService).join_session("127.0.0.1:%d" % PORT), OK)
	await wait_for_signal((host.session as SessionService).player_joined, 5.0)
	var host_clock: SessionClock = host.clock
	var original_day: int = host_clock.current_day

	(client.objective as LoopObjective).apply_session_snapshot.rpc(
		3, 9.0, false, int(LoopObjective.Outcome.STABLE_ESCAPE), true, true, true)
	await wait_physics_frames(10)

	assert_engine_error("!can_call", "authority RPC가 클라이언트 day 주장을 차단해야 한다")
	assert_eq(host_clock.current_day, original_day, "클라이언트 RPC로 호스트 day를 바꿀 수 없다")
	assert_eq((host.objective as LoopObjective).outcome, LoopObjective.Outcome.PENDING)


## 가짜 완료 금지 (설계서 15장): 세션 골격이 실제 게임 씬에 있어야 한다.
func test_main_scene_runs_the_loop_session() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(3)
	var clock: SessionClock = main.get_node_or_null("SessionClock") as SessionClock
	var objective: LoopObjective = main.get_node_or_null("LoopObjective") as LoopObjective

	assert_not_null(clock, "세션 시계가 실제 게임 씬에 있어야 한다")
	assert_not_null(objective, "루프 목표가 실제 게임 씬에 있어야 한다")
	assert_almost_eq(clock.day_duration_seconds(), 600.0, 0.01, "하루는 10분이다")
	assert_eq(clock.total_days, 3, "W6 세션은 3일이다")

	var player: Player = main.get_node("Player")
	assert_gt(objective.global_position.distance_to(player.global_position), 500.0,
		"지정 지점은 스폰에서 걸어가야 할 만큼 떨어져 있어야 한다")

	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = objective.global_position
	query.collision_mask = 1
	assert_true(objective.get_world_2d().direct_space_state.intersect_point(query).is_empty(),
		"지정 지점이 벽 안이면 루프를 완주할 수 없다")


func test_compressed_days_preserve_campfire_injury_and_inventory() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)
	var player: Player = main.get_node("Player")
	var clock: SessionClock = main.get_node("SessionClock")
	var site: CampfireSite = main.get_node("SurvivalDemo/CampfireSite")
	player.inventory.add_item(&"bandage", 2)
	assert_true(player.injury.apply_replicated(&"leg", &"laceration"))
	site.build_and_light()
	clock.speed_multiplier = 1200.0

	assert_true(await wait_until(func() -> bool: return clock.current_day == 3, 3.0))

	assert_true(site.campfire != null and site.campfire.is_lit)
	assert_true(player.injury.has_leg_laceration())
	assert_eq(player.inventory.count_of(&"bandage"), 2)

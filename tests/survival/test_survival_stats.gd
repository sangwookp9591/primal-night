extends GutTest

## 생존 수치 4종 최소 모델 (설계서 5.1, 계획서 W4-T3): 체온 / 수분 / 포만 / 피로.
## 불변식:
##   1. 수치가 바닥나도 죽지 않는다 — 단계적 악화만 있다 (설계서 5.1).
##   2. 피로·수분은 스태미나, 포만은 자연 체력 회복에 붙는다.
##   3. 체온은 모닥불 곁에서만 회복한다.
##   4. 시뮬레이션은 호스트 권위다. 클라이언트는 스냅샷만 받는다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const SurvivalStatsScript = preload("res://scripts/survival/survival_stats.gd")
const SurvivalConfigScript = preload("res://scripts/survival/survival_config.gd")
const StaminaComponentScript = preload("res://scripts/survival/stamina_component.gd")
const PORT: int = 8922

var _event_bus: Node = null
var _campfire_registry: Node = null


func before_each() -> void:
	_event_bus = get_node("/root/EventBus")
	_campfire_registry = get_node("/root/CampfireRegistry")
	_campfire_registry.clear_for_test()


func _make_config() -> SurvivalConfig:
	var config: SurvivalConfig = SurvivalConfigScript.new()
	config.max_stamina = 100.0
	config.stamina_run_drain = 20.0
	config.stamina_regen_idle = 15.0
	config.stamina_recover_threshold = 20.0
	config.water_drain_per_second = 1.0
	config.food_drain_per_second = 1.0
	config.temperature_drain_per_second = 1.0
	config.temperature_regen_near_fire = 10.0
	config.fatigue_gain_per_second = 1.0
	config.fatigue_gain_per_pixel = 0.1
	config.fatigue_recover_per_second = 2.0
	config.stat_warn_ratio = 0.5
	config.stat_danger_ratio = 0.25
	config.fatigue_run_drain_bonus = 1.0
	config.fatigue_regen_penalty = 0.8
	config.water_stamina_regen_penalty = 0.7
	config.stamina_regen_combined_penalty_cap = 0.9
	config.natural_health_regen_per_second = 2.0
	config.food_health_regen_penalty = 1.0
	return config


## Player 없이 도는 순수 수치 노드 (몸 좌표만 있으면 된다).
func _make_stats(config: SurvivalConfig) -> SurvivalStats:
	var body: Node2D = add_child_autofree(Node2D.new())
	var stats: SurvivalStats = SurvivalStatsScript.new()
	stats.config = config
	body.add_child(stats)
	return stats


## 1. 수치가 바닥나도 죽지 않는다 (설계서 5.1: 낮아졌다는 이유만으로 즉시 사망시키지 않는다).
func test_empty_stats_degrade_stages_but_never_kill() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	await wait_physics_frames(1)
	var stats: SurvivalStats = player.stats
	stats.config = _make_config()  # 테스트용 빠른 감소 수치

	# 아주 긴 시간을 태워 체온·수분·포만을 바닥낸다. 피로는 탈진까지 끌어올린다.
	for _tick: int in range(200):
		stats.simulate(1.0)
	stats.fatigue = SurvivalStats.STAT_MAX

	assert_almost_eq(stats.water, 0.0, 0.01, "수분은 0 까지만 떨어진다")
	assert_almost_eq(stats.food, 0.0, 0.01, "포만도 0 까지만 떨어진다")
	assert_almost_eq(stats.temperature, 0.0, 0.01, "체온도 0 까지만 떨어진다")
	for stat: StringName in SurvivalStats.STATS:
		assert_eq(stats.stage_of(stat), SurvivalStats.STAGE_DANGER,
			"바닥난 %s 는 위험 단계다" % stat)

	assert_true(player.health.is_alive(), "수치가 바닥나도 즉사하지 않는다 (설계서 5.1)")
	assert_eq(player.health.current_health, player.health.config.max_health,
		"수치 저하는 체력을 직접 깎지 않는다 — 단계적 악화만 한다")


## 단계는 양호 → 주의 → 위험으로 내려간다. 경계는 SurvivalConfig 에서 온다.
func test_stage_steps_down_through_warn_before_danger() -> void:
	var config: SurvivalConfig = _make_config()
	var stats: SurvivalStats = _make_stats(config)

	assert_eq(stats.stage_of(&"water"), SurvivalStats.STAGE_GOOD, "가득 찬 수치는 양호다")
	stats.water = 40.0  # 0.4 < 0.5(주의), >= 0.25(위험 아님)
	assert_eq(stats.stage_of(&"water"), SurvivalStats.STAGE_WARN, "절반 아래는 주의다")
	stats.water = 10.0
	assert_eq(stats.stage_of(&"water"), SurvivalStats.STAGE_DANGER, "4분의 1 아래는 위험이다")

	# 피로만 방향이 반대다 — 높을수록 나쁘다.
	stats.fatigue = 0.0
	assert_eq(stats.stage_of(&"fatigue"), SurvivalStats.STAGE_GOOD, "피로 0 은 양호다")
	stats.fatigue = 90.0
	assert_eq(stats.stage_of(&"fatigue"), SurvivalStats.STAGE_DANGER, "피로가 가득 차면 위험이다")


## 2. 피로는 움직일수록 쌓이고, 제자리에서 쉬면 풀린다.
func test_fatigue_grows_with_movement_and_recovers_while_resting() -> void:
	var config: SurvivalConfig = _make_config()
	var stats: SurvivalStats = _make_stats(config)
	var body: Node2D = stats.get_parent()

	# 10px 이동하며 1초: 기본(1.0) + 이동 거리분(10 * 0.1).
	body.global_position = Vector2(10.0, 0.0)
	stats.simulate(1.0)
	var short_move: float = stats.fatigue
	assert_almost_eq(short_move, 2.0, 0.01, "움직이면 지친다")

	# 100px 이동하며 1초: 훨씬 더 지친다 (이동 거리 비례).
	stats.fatigue = 0.0
	body.global_position = Vector2(110.0, 0.0)
	stats.simulate(1.0)
	assert_almost_eq(stats.fatigue, 11.0, 0.01, "많이 움직일수록 더 지친다")
	assert_gt(stats.fatigue, short_move, "달려서 더 멀리 가면 더 지친다")

	# 제자리에서 쉬면 풀린다 — 쉬는 것이 유일한 회복 수단이다.
	stats.fatigue = 50.0
	stats.simulate(1.0)
	assert_almost_eq(stats.fatigue, 48.0, 0.01, "제자리에서 쉬면 피로가 풀린다")


func _make_stamina(config: SurvivalConfig) -> StaminaComponent:
	var stamina: StaminaComponent = StaminaComponentScript.new()
	stamina.config = config
	add_child_autofree(stamina)
	return stamina


## 3. 피로는 달리기 효율과 스태미나 회복에 붙는다 (계획서 W4-T3의 유일한 행동 연결).
func test_fatigue_costs_more_stamina_to_run_and_slows_regen() -> void:
	var config: SurvivalConfig = _make_config()

	# 달리기 소모: 지친 쪽이 더 많이 쓴다.
	var rested_run: StaminaComponent = _make_stamina(config)
	var tired_run: StaminaComponent = _make_stamina(config)
	rested_run.update(true, true, 1.0, 0.0)
	tired_run.update(true, true, 1.0, 1.0)
	assert_lt(tired_run.current_stamina, rested_run.current_stamina,
		"피로하면 같은 달리기에 스태미나를 더 쓴다")

	# 회복: 지친 쪽이 더 느리게 찬다.
	var rested_regen: StaminaComponent = _make_stamina(config)
	var tired_regen: StaminaComponent = _make_stamina(config)
	rested_regen.current_stamina = 0.0
	tired_regen.current_stamina = 0.0
	rested_regen.update(false, false, 1.0, 0.0)
	tired_regen.update(false, false, 1.0, 1.0)
	assert_lt(tired_regen.current_stamina, rested_regen.current_stamina,
		"피로하면 스태미나 회복이 느리다")

	# 피로 인자를 넘기지 않는 옛 호출부(3인자)는 기존 동작 그대로다.
	var legacy: StaminaComponent = _make_stamina(config)
	legacy.update(true, true, 1.0)
	assert_almost_eq(legacy.current_stamina, rested_run.current_stamina, 0.01,
		"피로 인자를 넘기지 않으면 기존 동작 그대로다")


func test_dehydration_reduces_stamina_regeneration_without_stopping_it() -> void:
	var config: SurvivalConfig = _make_config()
	var hydrated: StaminaComponent = _make_stamina(config)
	var dehydrated: StaminaComponent = _make_stamina(config)
	hydrated.current_stamina = 0.0
	dehydrated.current_stamina = 0.0

	hydrated.update(false, false, 1.0, 0.0, 1.0)
	dehydrated.update(false, false, 1.0, 0.0, 0.0)

	assert_lt(dehydrated.current_stamina, hydrated.current_stamina)
	assert_gt(dehydrated.current_stamina, 0.0,
		"수분 0도 즉사·완전 정지가 아니라 스태미나 회복 저하다")


func test_fatigue_and_dehydration_regen_penalties_have_a_combined_cap() -> void:
	var config: SurvivalConfig = _make_config()
	var pressured: StaminaComponent = _make_stamina(config)
	pressured.current_stamina = 0.0

	pressured.update(false, false, 1.0, 1.0, 0.0)

	assert_almost_eq(pressured.current_stamina,
		config.stamina_regen_idle * (1.0 - config.stamina_regen_combined_penalty_cap),
		0.001, "피로와 탈수 페널티는 합산 상한을 넘어 폭주하지 않아야 한다")


func test_hunger_reduces_natural_health_regeneration() -> void:
	var config: SurvivalConfig = _make_config()
	var fed: SurvivalStats = _make_stats(config)
	var hungry: SurvivalStats = _make_stats(config)

	assert_almost_eq(fed.natural_health_regen_multiplier(), 1.0, 0.001)
	hungry.food = 0.0
	assert_almost_eq(hungry.natural_health_regen_multiplier(), 0.0, 0.001,
		"포만 0은 자연 체력 회복을 먼저 막되 직접 피해를 주지 않는다")


func test_player_natural_health_regen_uses_food_multiplier() -> void:
	var fed: Player = add_child_autofree(PlayerScene.instantiate())
	var hungry: Player = add_child_autofree(PlayerScene.instantiate())
	await wait_physics_frames(1)
	fed.health.take_damage(10.0)
	hungry.health.take_damage(10.0)
	fed.stats.food = SurvivalStats.STAT_MAX
	hungry.stats.food = 0.0

	fed.stats.simulate(1.0)
	hungry.stats.simulate(1.0)

	assert_gt(fed.health.current_health, hungry.health.current_health,
		"포만한 플레이어만 자연 체력 회복 효과를 받아야 한다")


## 4. 체온은 모닥불 곁에서만 회복한다 (설계서 5.1: 불의 영향).
func test_temperature_falls_but_recovers_near_a_lit_campfire() -> void:
	var config: SurvivalConfig = _make_config()
	var stats: SurvivalStats = _make_stats(config)
	stats.temperature = 50.0

	stats.simulate(1.0)
	assert_almost_eq(stats.temperature, 49.0, 0.01, "불이 없으면 체온이 떨어진다")

	# 모닥불이 켜졌다 — 늦게 생성된 소비자도 단일 레지스트리에서 읽는다.
	var campfire: Node2D = add_child_autofree(Node2D.new())
	_campfire_registry.register_fire(campfire, Vector2.ZERO, 200.0)
	stats.simulate(1.0)
	assert_gt(stats.temperature, 49.0, "불 곁에서는 체온이 회복된다")

	# 불이 꺼지면 다시 떨어진다.
	var warmed: float = stats.temperature
	_campfire_registry.unregister_fire(campfire)
	stats.simulate(1.0)
	assert_lt(stats.temperature, warmed, "불이 꺼지면 다시 식는다")


## 불 반경 밖이면 회복하지 않는다.
func test_temperature_does_not_recover_outside_the_fire_radius() -> void:
	var config: SurvivalConfig = _make_config()
	var stats: SurvivalStats = _make_stats(config)
	stats.temperature = 50.0
	var campfire: Node2D = add_child_autofree(Node2D.new())
	_campfire_registry.register_fire(campfire, Vector2(1000.0, 0.0), 200.0)

	stats.simulate(1.0)

	assert_lt(stats.temperature, 50.0, "멀리 있는 불은 몸을 데우지 못한다")


## 호스트 값으로 맞추되 범위 밖 값은 잘라낸다 (스냅샷 수신 경로).
func test_apply_replicated_clamps_to_stat_bounds() -> void:
	var stats: SurvivalStats = _make_stats(_make_config())

	stats.apply_replicated(30.0, 40.0, 50.0, 60.0)
	assert_almost_eq(stats.temperature, 30.0, 0.01)
	assert_almost_eq(stats.water, 40.0, 0.01)
	assert_almost_eq(stats.food, 50.0, 0.01)
	assert_almost_eq(stats.fatigue, 60.0, 0.01)

	stats.apply_replicated(9999.0, -5.0, 9999.0, 9999.0)
	assert_almost_eq(stats.temperature, SurvivalStats.STAT_MAX, 0.01, "상한 밖 값은 잘린다")
	assert_almost_eq(stats.water, 0.0, 0.01, "하한 밖 값도 잘린다")


## 6. 스냅샷 복제: 호스트가 굴린 4수치가 클라이언트 복제본에 도착한다.
## 실제 ENet 루프백 브랜치 2개 (tests/survival/test_net_survival.gd 관례).
func test_host_stats_replicate_to_client_avatar() -> void:
	var host: Dictionary = _make_side("HostSide")
	var client: Dictionary = _make_side("ClientSide")

	assert_eq((host.session as LocalSessionService).host_session(), OK)
	assert_eq((client.session as LocalSessionService).join_session("127.0.0.1:%d" % PORT), OK)
	await wait_for_signal((host.session as SessionService).player_joined, 5.0, "호스트가 참가를 관측해야 한다")
	var client_id: StringName = (client.session as SessionService).get_local_player_id()
	assert_true(await wait_until(func() -> bool:
		return (host.container as Node2D).has_node(NodePath(String(client_id))) \
			and (client.container as Node2D).has_node(NodePath(String(client_id))), 5.0),
		"양쪽에 클라이언트 아바타가 스폰되어야 한다")

	# 호스트 권위 아바타의 수치를 흔든다.
	var authority_avatar: Player = (host.container as Node2D).get_node(String(client_id))
	authority_avatar.stats.apply_replicated(33.0, 44.0, 55.0, 66.0)

	var replica: Player = (client.container as Node2D).get_node(String(client_id))
	assert_true(await wait_until(func() -> bool:
		return absf(replica.stats.water - 44.0) < 1.0, 5.0),
		"호스트가 굴린 생존 수치가 클라이언트 복제본에 도착해야 한다")
	assert_almost_eq(replica.stats.temperature, 33.0, 1.0, "체온도 복제된다")
	assert_almost_eq(replica.stats.food, 55.0, 1.0, "포만도 복제된다")
	assert_almost_eq(replica.stats.fatigue, 66.0, 1.0, "피로도 복제된다")

	# ★ 시뮬레이션은 호스트 권위다 (설계서 7.2). 클라이언트 기계에서 물리 틱을 억지로
	# 돌려도 복제본은 스스로 수치를 굴리지 않는다 — 양쪽이 각자 굴리면 값이 갈라진다.
	var before_water: float = replica.stats.water
	replica.stats._physics_process(30.0)
	assert_almost_eq(replica.stats.water, before_water, 0.001,
		"클라이언트는 생존 수치를 시뮬레이션하지 않고 호스트 스냅샷만 받는다")

	(client.session as SessionService).leave_session()
	(host.session as SessionService).leave_session()
	get_tree().set_multiplayer(null, (host.root as Node).get_path())
	get_tree().set_multiplayer(null, (client.root as Node).get_path())


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

	var survival: NetSurvival = NetSurvival.new()
	survival.name = "NetSurvival"
	survival.session_path = ^"../NetSession"
	survival.host_player_path = ^"../Player"
	survival.players_container_path = ^"../Players"
	root.add_child(survival)

	return { root = root, session = session, host_player = host_player,
		container = container, net_move = net_move, survival = survival }


## 7. HUD 는 숫자가 아니라 4수치의 단계를 보여준다 (설계서 10.1, 회색 상자).
func test_hud_shows_stage_labels_for_all_four_stats() -> void:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var hud: Hud = preload("res://scenes/ui/hud/hud.tscn").instantiate()
	world.add_child(hud)
	await wait_physics_frames(1)
	hud.bind(player)

	for stat: StringName in SurvivalStats.STATS:
		assert_eq(hud.stat_stage_text(stat), SurvivalStats.STAGE_GOOD,
			"%s 는 처음에 양호로 표시된다" % stat)

	player.stats.water = 5.0
	player.stats.fatigue = 95.0
	await wait_physics_frames(2)

	assert_eq(hud.stat_stage_text(&"water"), SurvivalStats.STAGE_DANGER,
		"수분이 바닥나면 HUD 단계가 위험으로 바뀐다")
	assert_eq(hud.stat_stage_text(&"fatigue"), SurvivalStats.STAGE_DANGER,
		"피로가 가득 차면 HUD 단계가 위험으로 바뀐다")
	assert_eq(hud.stat_stage_text(&"food"), SurvivalStats.STAGE_GOOD,
		"멀쩡한 수치는 그대로 양호다")

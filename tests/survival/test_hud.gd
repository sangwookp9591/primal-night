extends GutTest

## HUD: 체력 / 스태미나 / 인벤토리 8칸 / 출혈 상태.
## ★ 표시 수치는 반드시 데이터 리소스에서 생성한다. UI 에 하드코딩 금지 (설계서 5.6/15장).
## ★ 숫자 나열보다 단계 표시 (설계서 10.1).

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const HudScene: PackedScene = preload("res://scenes/ui/hud/hud.tscn")

var _game_data: Node = null

func before_each() -> void:
	_game_data = get_node("/root/GameData")

func _spawn() -> Array:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var hud: Hud = HudScene.instantiate()
	world.add_child(hud)
	await wait_physics_frames(1)
	hud.bind(player)
	return [player, hud]

func test_shows_eight_inventory_slots() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]

	assert_eq(player.inventory.slot_count, 8, "전제: 인벤토리는 8칸")
	for i: int in range(8):
		assert_eq(hud.slot_text(i), "", "빈 슬롯은 비어 보여야 한다")

## ★ 슬롯 표시는 ItemData.display_name 에서 생성된다. HUD 에 이름을 적어두지 않는다.
func test_slot_text_comes_from_item_data_not_from_the_hud() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]
	var stone: ItemData = _game_data.get_item(&"stone")

	player.inventory.add_item(&"stone", 4)

	var text: String = hud.slot_text(0)
	assert_string_contains(text, stone.display_name, "표시 이름은 ItemData 에서 와야 한다")
	assert_string_contains(text, "4", "수량이 표시되어야 한다")

## 데이터의 표시 이름을 바꾸면 HUD 도 따라 바뀌어야 한다 (하드코딩이면 안 따라온다).
func test_hud_follows_the_data_when_display_name_changes() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]
	var stone: ItemData = _game_data.get_item(&"stone")
	var original: String = stone.display_name
	stone.display_name = "조약돌"

	player.inventory.add_item(&"stone", 1)
	var text: String = hud.slot_text(0)

	stone.display_name = original  # 전역 리소스이므로 되돌린다
	assert_string_contains(text, "조약돌", "HUD 는 데이터를 그대로 읽어야 한다 (하드코딩 금지)")

## ★ 설계서 10.1: 숫자 나열보다 단계 표시. 경계값은 SurvivalConfig 에서 온다.
func test_health_is_shown_as_a_stage_not_a_bare_number() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]
	var config: SurvivalConfig = player.health.config

	assert_eq(hud.stage_label_for_health(), "양호", "가득 찬 체력은 양호")

	player.health.current_health = config.max_health * (config.health_hurt_ratio - 0.01)
	assert_eq(hud.stage_label_for_health(), "부상", "부상 경계 아래면 부상")

	player.health.current_health = config.max_health * (config.health_critical_ratio - 0.01)
	assert_eq(hud.stage_label_for_health(), "위독", "위독 경계 아래면 위독")

func test_bleeding_indicator_follows_the_bleeding_state() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]

	assert_false(hud.bleeding_visible(), "출혈 중이 아니면 표시하지 않는다")

	player.health.start_bleeding()
	await wait_physics_frames(1)
	assert_true(hud.bleeding_visible(), "출혈 중이면 표시해야 한다")

	player.health.stop_bleeding()
	await wait_physics_frames(1)
	assert_false(hud.bleeding_visible(), "지혈되면 표시를 끈다")

## HUD 는 인벤토리 changed 신호로 갱신한다 (매 프레임 폴링 금지, 성능문서 6.2).
func test_slots_refresh_on_the_inventory_changed_signal() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]

	player.inventory.add_item(&"wood", 2)

	# 프레임을 돌리지 않았는데도 이미 갱신되어 있어야 한다 = 신호 기반이다.
	var wood: ItemData = _game_data.get_item(&"wood")
	assert_string_contains(hud.slot_text(0), wood.display_name, "changed 신호를 받아 즉시 갱신되어야 한다")


## ── 세션 목표 HUD (W5-T2): 남은 시간 / 현재 조건 / 성공·실패 ─────────────────────

## LoopObjective._ready 가 요구하는 최소 골격(세션·시계·컨테이너)을 갖춘 작은 월드.
func _spawn_session() -> Dictionary:
	var root: Node = add_child_autofree(Node.new())
	root.name = "SessionWorld"

	var session: LocalSessionService = LocalSessionService.new()
	session.name = "NetSession"
	session.config = NetConfig.new()
	root.add_child(session)

	var player: Player = PlayerScene.instantiate()
	player.name = "Player"
	root.add_child(player)

	var container: Node2D = Node2D.new()
	container.name = "Players"
	root.add_child(container)

	var clock: SessionClock = SessionClock.new()
	clock.name = "SessionClock"
	clock.phase_duration_seconds = 720.0
	root.add_child(clock)

	var objective: LoopObjective = LoopObjective.new()
	objective.name = "LoopObjective"
	objective.clock_path = ^"../SessionClock"
	objective.session_path = ^"../NetSession"
	objective.host_player_path = ^"../Player"
	objective.players_container_path = ^"../Players"
	root.add_child(objective)

	var hud: Hud = HudScene.instantiate()
	root.add_child(hud)
	await wait_physics_frames(1)
	hud.bind(player)
	hud.bind_session(objective)
	return {root = root, player = player, clock = clock, objective = objective, hud = hud}


## 남은 시간은 mm:ss 로 표시한다 (숫자를 HUD 가 만들지 않고 시계에서 읽는다).
func test_session_time_is_shown_as_mmss_from_the_clock() -> void:
	var s: Dictionary = await _spawn_session()
	var clock: SessionClock = s.clock
	var hud: Hud = s.hud

	clock.stop()  # 자동 카운트다운을 멈춰 값을 고정한다.
	clock.remaining_seconds = 125.0
	hud._refresh_session()

	assert_eq(hud.session_time_text(), "02:05", "남은 시간을 시계 값에서 mm:ss 로 표시한다")


## 현재 조건은 목표 상태를 따라 바뀐다 (문자열은 도메인이 소유, HUD 는 읽어 그린다).
func test_session_condition_follows_the_objective_state() -> void:
	var s: Dictionary = await _spawn_session()
	var objective: LoopObjective = s.objective
	var hud: Hud = s.hud

	hud._refresh_session()
	assert_eq(hud.session_condition_text(), String(LoopObjective.CONDITION_EXPOSE),
		"노출 전에는 노출 조건을 보여준다")

	objective.mark_risk_exposed()
	hud._refresh_session()
	assert_eq(hud.session_condition_text(), String(LoopObjective.CONDITION_OBSERVE),
		"노출 뒤에는 랩터 관측 조건으로 바뀐다")


## 성공/실패는 outcome_changed 신호로만 갱신한다 (매 프레임 폴링 금지).
func test_session_outcome_updates_on_settlement() -> void:
	var s: Dictionary = await _spawn_session()
	var objective: LoopObjective = s.objective
	var clock: SessionClock = s.clock
	var hud: Hud = s.hud

	assert_eq(hud.session_outcome_text(), "", "판정 전에는 결과를 비워둔다")

	objective.mark_risk_exposed()
	clock.advance(clock.phase_duration_seconds + 1.0)  # 시간 만료 → 실패.
	await wait_physics_frames(2)

	assert_eq(hud.session_outcome_text(), String(LoopObjective.CONDITION_FAILED),
		"시간 만료로 실패가 확정되면 결과를 표시한다")

extends GutTest

## NetSurvival — 피해·출혈 호스트 권위 + 생존 상태 복제 (설계서 7.2/7.4, 5.2).
## 실제 ENet 루프백 브랜치 2개(호스트 기계/클라이언트 기계)로 검증한다.
## 핵심: 클라이언트가 보낸 피해량을 그대로 믿지 않고, 피 냄새는 권위(호스트)만 발신한다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const PORT: int = 8917

var host: Dictionary
var client: Dictionary
var _event_bus: Node = null


func before_each() -> void:
	_event_bus = get_node("/root/EventBus")
	host = _make_side("HostSide")
	client = _make_side("ClientSide")


func after_each() -> void:
	client.session.leave_session()
	host.session.leave_session()
	get_tree().set_multiplayer(null, host.root.get_path())
	get_tree().set_multiplayer(null, client.root.get_path())


## 한쪽 '기계': 세션 + 호스트 아바타 + 스폰 컨테이너 + NetMovement + NetSurvival.
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

	return {
		root = root, session = session, host_player = host_player,
		container = container, net_move = net_move, survival = survival,
	}


func _join_and_spawn() -> StringName:
	assert_eq(host.session.host_session(), OK)
	assert_eq(client.session.join_session("127.0.0.1:%d" % PORT), OK)
	await wait_for_signal(host.session.player_joined, 5.0, "호스트가 참가를 관측해야 한다")
	var client_id: StringName = client.session.get_local_player_id()
	assert_true(await wait_until(func() -> bool:
		return host.container.has_node(NodePath(String(client_id))) \
			and client.container.has_node(NodePath(String(client_id))), 5.0),
		"양쪽에 클라이언트 아바타가 스폰되어야 한다")
	return client_id


## ★ 클라이언트가 주장한 피해량(10000)을 그대로 믿지 않는다 (설계서 7.4).
## 호스트는 자기 규칙(remote_hurt_max_damage)으로 잘라서만 적용한다.
## (뮤테이션 자가검증 3번: 주장값을 그대로 신뢰하게 바꾸면 이 테스트가 잡는다.)
func test_client_claimed_damage_is_clamped_to_host_rule() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view: Player = host.container.get_node(String(client_id))
	var max_health: float = host_view.health.config.max_health
	var max_damage: float = host_view.health.config.remote_hurt_max_damage

	(client.survival as NetSurvival).request_hurt_for(client_avatar, 10000.0)

	assert_true(await wait_until(func() -> bool:
		return host_view.health.is_bleeding, 5.0),
		"호스트가 부상 의도를 확정하고 출혈을 시작해야 한다")
	assert_true(host_view.health.is_alive(), "변조된 10000 피해가 적용됐다면 죽었을 것이다")
	# 확정 직후 출혈 지속 피해가 조금 이어질 수 있다 — 상한만 정확히 본다.
	assert_lte(host_view.health.current_health, max_health - max_damage,
		"호스트 규칙만큼은 피해를 입어야 한다")
	assert_gt(host_view.health.current_health, max_health - max_damage - 3.0,
		"호스트 규칙(%.0f)을 넘는 피해가 적용되면 안 된다" % max_damage)
	assert_true(host_view.injury.has_leg_laceration(), "호스트만 다리 열상 부위를 확정해야 한다")


func test_client_cannot_directly_confirm_injury_body_part_or_effect() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))

	assert_false(client_avatar.injury.apply_host_leg_laceration(0.0),
		"클라이언트 복제본은 부위·효과를 직접 확정할 수 없어야 한다")
	assert_false(client_avatar.injury.has_leg_laceration())


## ★ 피 냄새는 권위(호스트)만 발신한다 (설계서 7.2: 냄새 이벤트는 호스트 권한).
## 클라이언트 복제본이 함께 발신하면 냄새가 2배로 쌓인다.
## (뮤테이션 자가검증 2번: 게이트를 제거하면 이 테스트가 잡는다.)
func test_bleed_smell_is_emitted_only_by_the_authority() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view: Player = host.container.get_node(String(client_id))
	var interval: float = host_view.health.config.bleed_smell_interval

	# 양쪽 다 출혈 상태로 만든다 (복제와 무관하게 발신 게이트만 본다).
	host_view.health.start_bleeding()
	client_avatar.health.start_bleeding()
	watch_signals(_event_bus)

	host_view.health._process(interval)
	assert_signal_emit_count(_event_bus, "smell_emitted", 1, "권위(호스트 기계)는 발신한다")

	client_avatar.health._process(interval)
	assert_signal_emit_count(_event_bus, "smell_emitted", 1,
		"클라이언트 기계는 발신하지 않는다 — 발신하면 냄새가 2배로 쌓인다")


## 호스트가 확정한 체력·출혈 상태가 클라이언트 복제본으로 전파된다 (HUD·치료 판정용).
func test_survival_state_replicates_to_client() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view: Player = host.container.get_node(String(client_id))

	(client.survival as NetSurvival).request_hurt_for(client_avatar, 25.0)

	assert_true(await wait_until(func() -> bool:
		return client_avatar.health.is_bleeding \
			and absf(client_avatar.health.current_health - host_view.health.current_health) < 2.0 \
			and client_avatar.health.current_health < client_avatar.health.config.max_health, 5.0),
		"클라이언트 복제본이 호스트 확정 체력·출혈 상태로 수렴해야 한다")
	assert_true(client_avatar.health.is_bleeding, "출혈 상태가 복제되어야 한다")
	assert_true(client_avatar.injury.has_leg_laceration(), "호스트 확정 다리 열상이 복제되어야 한다")


func test_poison_status_snapshot_updates_client_state_visual() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view: Player = host.container.get_node(String(client_id))
	host_view.stats.apply_food_risk(false, 1.0)

	assert_true(await wait_until(func() -> bool:
		return client_avatar.stats.poison_remaining > 0.0 \
			and client_avatar.stats._active_state_visual == &"poison_state" \
			and client_avatar.visual_rig.state_overlay.visible, 5.0),
		"호스트 중독 상태 스냅샷이 클라이언트 얼굴 오버레이까지 갱신해야 한다")


func test_client_consume_is_host_validated_and_replicated() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view: Player = host.container.get_node(String(client_id))
	host_view.inventory.add_item(&"raw_meat", 2)
	client_avatar.inventory.add_item(&"raw_meat", 2)
	host_view.stats.food = 20.0
	client_avatar.stats.food = 20.0
	var nutrition: float = (get_node("/root/GameData").get_item(&"raw_meat") as ItemData).nutrition

	(client.survival as NetSurvival).request_consume_for(client_avatar, &"raw_meat")

	assert_true(await wait_until(func() -> bool:
		return host_view.inventory.count_of(&"raw_meat") == 1 \
			and client_avatar.inventory.count_of(&"raw_meat") == 1, 5.0),
		"호스트가 정확히 1개 소비를 확정해 양쪽에 복제해야 한다")
	assert_almost_eq(host_view.stats.food, 20.0 + nutrition, 1.0,
		"회복량은 호스트 ItemData에서 와야 한다")
	assert_almost_eq(client_avatar.stats.food, host_view.stats.food, 2.0,
		"클라이언트 포만도도 호스트 확정값으로 수렴해야 한다")


func test_consume_without_authority_inventory_is_rejected() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view: Player = host.container.get_node(String(client_id))
	client_avatar.inventory.add_item(&"raw_meat", 1)
	host_view.stats.food = 20.0

	(client.survival as NetSurvival).request_consume_for(client_avatar, &"raw_meat")
	await wait_physics_frames(30)

	assert_eq(host_view.inventory.count_of(&"raw_meat"), 0)
	assert_eq(client_avatar.inventory.count_of(&"raw_meat"), 1,
		"클라이언트 복제본만 가진 아이템 주장은 소비 확정되면 안 된다")
	assert_lt(host_view.stats.food, 21.0, "호스트 포만 회복도 없어야 한다")


func _host_id() -> StringName:
	return host.session.get_local_player_id()


## ★ 클라이언트가 호스트를 붕대로 치료한다 — 실제 Interactor 홀드 전 구간 (설계서 5.2).
## 호스트가 세션·홀드 시간·붕대·거리를 검증해 확정하고, 결과가 양쪽에 복제된다.
func test_client_healer_completes_full_hold_and_host_confirms() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	var client_view_host: Player = client.host_player

	# 호스트 플레이어가 출혈 중 (권위 상태) → 복제로 클라이언트 화면에도 보인다.
	(host.host_player as Player).injury.apply_host_leg_laceration(0.0)
	assert_true(await wait_until(func() -> bool:
		return client_view_host.health.is_bleeding, 5.0), "출혈이 클라이언트로 복제되어야 한다")
	# 붕대: 호스트 권위 인벤토리와 클라이언트 복제본 (이전 획득을 시뮬레이션).
	host_view_client.inventory.add_item(&"bandage", 1)
	client_avatar.inventory.add_item(&"bandage", 1)
	await wait_physics_frames(2)

	# 클라이언트 기계에서 실제 상호작용: 대상 탐색 → 길게 누르기 → 완료.
	var target: Node = client_avatar.interactor.find_target()
	assert_not_null(target, "클라이언트가 출혈 중인 호스트의 HealTarget 을 찾아야 한다")
	client_avatar.interactor.begin()
	# 홀드 시작 직후: 호스트 기계의 환자(호스트 플레이어)도 이동이 잠겨야 한다.
	assert_true(await wait_until(func() -> bool:
		return (host.host_player as Player).movement_locked, 5.0),
		"치료받는 쪽(호스트 기계의 환자) 이동이 잠겨야 한다")

	# 홀드 완료까지 실제 프레임으로 기다린다 (2.0초 + 여유).
	assert_true(await wait_until(func() -> bool:
		return not (host.host_player as Player).health.is_bleeding, 8.0),
		"호스트가 치료를 확정해 출혈이 멈춰야 한다")
	assert_true(await wait_until(func() -> bool:
		return host_view_client.inventory.count_of(&"bandage") == 0 \
			and client_avatar.inventory.count_of(&"bandage") == 0, 5.0),
		"붕대 1개 소비가 양쪽에 복제되어야 한다")
	assert_true(await wait_until(func() -> bool:
		return not client_view_host.health.is_bleeding, 5.0),
		"지혈 상태가 클라이언트로 복제되어야 한다")
	assert_false((host.host_player as Player).injury.has_leg_laceration(),
		"호스트 치료 확정은 다리 열상도 해소해야 한다")
	assert_false(client_view_host.injury.has_leg_laceration(),
		"열상 해소가 클라이언트에도 복제되어야 한다")
	assert_true(await wait_until(func() -> bool:
		return not (host.host_player as Player).movement_locked \
			and not client_avatar.movement_locked, 5.0),
		"치료가 끝나면 양쪽 이동 잠금이 풀려야 한다")


## 세션 없는 커밋(변조)은 거부된다 — 붕대도 출혈도 그대로.
func test_heal_commit_without_session_is_rejected() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_view_client: Player = host.container.get_node(String(client_id))
	host_view_client.injury.apply_host_leg_laceration(0.0)
	(host.host_player as Player).inventory.add_item(&"bandage", 1)

	(host.survival as NetSurvival)._host_heal_commit(_host_id(), StringName(String(client_id)))
	await wait_physics_frames(10)

	assert_true(host_view_client.health.is_bleeding, "세션 없는 커밋으로는 낫지 않는다")
	assert_eq((host.host_player as Player).inventory.count_of(&"bandage"), 1, "붕대를 소비하면 안 된다")


## 홀드 시간을 기다리지 않은 즉시 커밋(변조)은 거부된다 (호스트 시계 기준).
func test_heal_commit_before_hold_time_is_rejected() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	(host.host_player as Player).health.start_bleeding()
	host_view_client.inventory.add_item(&"bandage", 1)
	client_avatar.inventory.add_item(&"bandage", 1)

	# 변조 클라이언트: 시작 직후 즉시 커밋을 보낸다.
	(client.survival as NetSurvival).request_heal_start.rpc_id(1, String(_host_id()))
	(client.survival as NetSurvival).request_heal_commit.rpc_id(1, String(_host_id()))
	await wait_physics_frames(30)

	assert_true((host.host_player as Player).health.is_bleeding, "홀드 시간 미달 커밋으로는 낫지 않는다")
	assert_eq(host_view_client.inventory.count_of(&"bandage"), 1, "붕대를 소비하면 안 된다")


## 치료 중 붕대를 다른 곳에 써 버리면 커밋이 거부된다 (설계서 5.2 경계).
func test_heal_commit_fails_when_bandage_was_consumed_mid_hold() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_view_client: Player = host.container.get_node(String(client_id))
	var patient_id: StringName = StringName(String(client_id))
	host_view_client.injury.apply_host_leg_laceration(0.0)
	(host.host_player as Player).inventory.add_item(&"bandage", 1)
	var survival: NetSurvival = host.survival

	survival._host_heal_start(_host_id(), patient_id)
	# 홀드 도중 붕대가 다른 곳에 쓰였다.
	(host.host_player as Player).inventory.remove_item(&"bandage", 1)
	# 홀드 시간은 충분히 지난 것으로 되감는다 (호스트 틱 시계 화이트박스).
	if survival._heal_sessions.has(_host_id()):
		survival._heal_sessions[_host_id()].start_ticks -= 300
	survival._host_heal_commit(_host_id(), patient_id)
	await wait_physics_frames(10)

	assert_true(host_view_client.health.is_bleeding, "붕대 없이 커밋되면 안 된다")


## ★ 치료 중 대상이 죽으면 세션이 끊기고 원격 환자의 이동 잠금도 풀린다 (설계서 5.2 경계).
func test_patient_death_mid_hold_cancels_session_and_unlocks_remote_patient() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	var patient_id: StringName = StringName(String(client_id))
	host_view_client.injury.apply_host_leg_laceration(0.0)
	(host.host_player as Player).inventory.add_item(&"bandage", 1)
	var survival: NetSurvival = host.survival

	# 호스트가 클라이언트를 치료하기 시작한다 → 원격 환자(클라이언트 기계) 잠금.
	survival._host_heal_start(_host_id(), patient_id)
	assert_true(await wait_until(func() -> bool:
		return client_avatar.movement_locked, 5.0),
		"치료받는 쪽(클라이언트 기계의 로컬 아바타) 이동이 잠겨야 한다")

	# 치료 중 대상이 죽는다.
	host_view_client.health.take_damage(1000.0, &"test")
	assert_true(await wait_until(func() -> bool:
		return not client_avatar.movement_locked, 5.0),
		"대상이 죽으면 세션이 끊기고 원격 잠금이 풀려야 한다")

	# 죽은 뒤의 커밋은 거부된다.
	survival._host_heal_commit(_host_id(), patient_id)
	await wait_physics_frames(10)
	assert_eq((host.host_player as Player).inventory.count_of(&"bandage"), 1, "죽은 대상에게 붕대를 소비하면 안 된다")


## 치료 중 환자가 세션을 이탈하면 치료가 끊긴다 (설계서 5.2/7.3 경계).
func test_patient_leaving_session_cancels_heal() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_view_client: Player = host.container.get_node(String(client_id))
	var patient_id: StringName = StringName(String(client_id))
	host_view_client.injury.apply_host_leg_laceration(0.0)
	(host.host_player as Player).inventory.add_item(&"bandage", 1)
	var survival: NetSurvival = host.survival

	survival._host_heal_start(_host_id(), patient_id)
	client.session.leave_session()
	await wait_for_signal(host.session.player_left, 5.0, "호스트가 이탈을 관측해야 한다")
	await wait_physics_frames(10)

	assert_false(survival._heal_sessions.has(_host_id()), "환자가 이탈하면 세션이 정리되어야 한다")
	assert_false((host.host_player as Player).movement_locked, "치료자 잠금이 풀려야 한다")

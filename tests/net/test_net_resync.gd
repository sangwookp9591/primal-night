extends GutTest

## NetResync — 재접속 전체 상태 재동기화 (설계서 6.3/7.3, W2-T5).
## 실제 ENet 루프백 브랜치 2개(호스트 기계/클라이언트 기계)로 검증한다.
## 핵심 불변식:
##   1. 재접속한 플레이어는 인벤토리·체력·출혈·위치를 되찾는다 (호스트가 스냅샷 전송).
##   2. 재접속 중 아이템 총합이 변하지 않는다 — 복제 0, 소실 0.
##   3. 이탈 유예(30초 despawn) 뒤 돌아와도 슬롯(120초)이 살아 있으면 상태를 복원한다.
##   4. 슬롯 만료(120초) 뒤 돌아오면 새 플레이어다 (설계서 6.3: 미복귀 연결 종료).
##   5. 재접속한 피어의 의도 RPC(줍기·부상)가 다시 동작한다 (RpcGuard 재등록).

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")
const NetTestPortsScript = preload("res://tests/net/net_test_ports.gd")

var port: int
var host: Dictionary
var client: Dictionary


func before_each() -> void:
	port = NetTestPortsScript.pick_available_port(2)
	host = _make_side("HostSide")
	client = _make_side("ClientSide")


func after_each() -> void:
	client.session.leave_session()
	host.session.leave_session()
	get_tree().set_multiplayer(null, host.root.get_path())
	get_tree().set_multiplayer(null, client.root.get_path())


## 한쪽 '기계': 세션 + 아바타 + NetMovement + NetPickup + NetSurvival + NetResync.
func _make_side(side_name: String) -> Dictionary:
	var root: Node = add_child_autofree(Node.new())
	root.name = side_name
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())

	var session: LocalSessionService = LocalSessionService.new()
	session.name = "NetSession"
	session.config = NetConfig.new()
	session.config.port = port
	root.add_child(session)

	var host_player: Player = PlayerScene.instantiate()
	host_player.name = "Player"
	root.add_child(host_player)

	var container: Node2D = Node2D.new()
	container.name = "Players"
	root.add_child(container)

	var items: Node2D = Node2D.new()
	items.name = "Items"
	root.add_child(items)

	var net_move: NetMovement = NetMovement.new()
	net_move.name = "NetMovement"
	net_move.session_path = ^"../NetSession"
	net_move.host_player_path = ^"../Player"
	net_move.players_container_path = ^"../Players"
	net_move.avatar_scene = PlayerScene
	net_move.config = session.config
	root.add_child(net_move)

	var pickup: NetPickup = NetPickup.new()
	pickup.name = "NetPickup"
	pickup.session_path = ^"../NetSession"
	pickup.host_player_path = ^"../Player"
	pickup.players_container_path = ^"../Players"
	pickup.world_root_path = ^".."
	root.add_child(pickup)

	var survival: NetSurvival = NetSurvival.new()
	survival.name = "NetSurvival"
	survival.session_path = ^"../NetSession"
	survival.host_player_path = ^"../Player"
	survival.players_container_path = ^"../Players"
	root.add_child(survival)

	var resync: NetResync = NetResync.new()
	resync.name = "NetResync"
	resync.session_path = ^"../NetSession"
	resync.host_player_path = ^"../Player"
	resync.players_container_path = ^"../Players"
	root.add_child(resync)

	return {
		root = root, session = session, host_player = host_player,
		container = container, items = items, net_move = net_move,
		pickup = pickup, survival = survival, resync = resync,
	}


func _join_and_spawn() -> StringName:
	assert_eq(host.session.host_session(), OK)
	assert_eq(client.session.join_session("127.0.0.1:%d" % port), OK)
	await wait_for_signal(host.session.player_joined, 5.0, "호스트가 참가를 관측해야 한다")
	var client_id: StringName = client.session.get_local_player_id()
	assert_true(await wait_until(func() -> bool:
		return host.container.has_node(NodePath(String(client_id))) \
			and client.container.has_node(NodePath(String(client_id))), 5.0),
		"양쪽에 클라이언트 아바타가 스폰되어야 한다")
	return client_id


## 같은 PlayerId 로 로컬 세션에 다시 참가한다 (설계서 6.3: 동일 계정 복귀).
func _rejoin(client_id: StringName) -> void:
	assert_eq(client.session.join_session({
		address = "127.0.0.1", port = port, player_id = client_id,
	}), OK, "재참가가 시작되어야 한다")


func _avatar_on(side: Dictionary, client_id: StringName) -> Player:
	return (side.container as Node2D).get_node_or_null(String(client_id)) as Player


## 이탈 유예(30초) 안의 재접속: 호스트 아바타가 살아 있고, 클라이언트는
## 빈 복제본으로 돌아온다 → 호스트 스냅샷으로 인벤토리·체력·출혈을 되찾는다.
func test_reconnect_within_grace_restores_client_replica() -> void:
	var client_id: StringName = await _join_and_spawn()
	var authority_avatar: Player = _avatar_on(host, client_id)
	authority_avatar.inventory.add_item(&"stone", 5)
	authority_avatar.inventory.add_item(&"bandage", 2)
	authority_avatar.health.take_damage(30.0, &"debug")
	authority_avatar.injury.apply_host_leg_laceration(0.0)

	client.session.leave_session()
	assert_true(await wait_until(func() -> bool:
		return host.session.get_players().size() == 1, 5.0), "호스트가 이탈을 관측해야 한다")
	assert_true(host.session.has_reconnect_slot(client_id), "120초 재접속 슬롯이 열려야 한다")

	_rejoin(client_id)
	await wait_for_signal(host.session.player_reconnected, 5.0, "재접속으로 관측되어야 한다")
	assert_true(await wait_until(func() -> bool:
		return _avatar_on(client, client_id) != null, 5.0), "클라이언트 아바타가 다시 스폰되어야 한다")
	var restored_replica: Player = _avatar_on(client, client_id)

	# ★ 인벤토리 복원 — 주기 동기화가 없는 유일한 상태라 재접속 스냅샷만이 경로다.
	# (뮤테이션 자가검증 3번: 스냅샷에서 인벤토리를 빼먹으면 이 검증이 잡는다.)
	assert_true(await wait_until(func() -> bool:
		return restored_replica.inventory.count_of(&"stone") == 5 \
			and restored_replica.inventory.count_of(&"bandage") == 2, 5.0),
		"재접속한 클라이언트가 인벤토리를 되찾아야 한다")
	assert_true(await wait_until(func() -> bool:
		return restored_replica.health.is_bleeding, 5.0), "출혈 상태를 되찾아야 한다")
	assert_true(restored_replica.injury.has_leg_laceration(), "동일한 다리 열상 상태를 되찾아야 한다")
	assert_true(restored_replica.health.current_health < 100.0, "체력 손실도 복원되어야 한다")

	# ★ 총합 불변식: 호스트 권위 인벤토리는 재접속으로 늘지도 줄지도 않는다.
	assert_eq(authority_avatar.inventory.count_of(&"stone"), 5, "재접속으로 아이템이 복제·소실되면 안 된다")
	assert_eq(authority_avatar.inventory.count_of(&"bandage"), 2, "재접속으로 아이템이 복제·소실되면 안 된다")


## 이탈 유예가 지나 아바타가 제거된 뒤(30초~120초 창)의 재접속:
## 호스트가 이탈 시점 상태를 보관했다가 새 아바타에 복원하고 스냅샷을 보낸다.
func test_reconnect_after_despawn_restores_saved_state() -> void:
	var client_id: StringName = await _join_and_spawn()
	var authority_avatar: Player = _avatar_on(host, client_id)
	authority_avatar.inventory.add_item(&"stone", 5)
	authority_avatar.health.take_damage(30.0, &"debug")
	authority_avatar.injury.apply_host_leg_laceration(0.0)
	authority_avatar.stats.apply_replicated(72.0, 61.0, 53.0, 44.0)
	var saved_health: float = authority_avatar.health.current_health
	authority_avatar.global_position = Vector2(400.0, 300.0)

	client.session.leave_session()
	assert_true(await wait_until(func() -> bool:
		return host.session.get_players().size() == 1, 5.0), "호스트가 이탈을 관측해야 한다")
	# 이탈 유예(30초)를 앞당긴다 — 아바타가 제거되는 실제 시나리오.
	host.net_move._tick_pending_despawns(31.0)
	assert_true(await wait_until(func() -> bool:
		return _avatar_on(host, client_id) == null, 5.0), "유예가 지나면 아바타가 제거된다")
	assert_true(host.session.has_reconnect_slot(client_id), "슬롯(120초)은 아직 살아 있다")

	_rejoin(client_id)
	await wait_for_signal(host.session.player_reconnected, 5.0, "재접속으로 관측되어야 한다")
	assert_true(await wait_until(func() -> bool:
		return _avatar_on(host, client_id) != null, 5.0), "호스트에 새 아바타가 스폰되어야 한다")
	var fresh_avatar: Player = _avatar_on(host, client_id)

	# 호스트 권위 상태가 보관본에서 복원되어야 한다.
	assert_true(await wait_until(func() -> bool:
		return fresh_avatar.inventory.count_of(&"stone") == 5, 5.0),
		"보관된 인벤토리가 새 아바타에 복원되어야 한다")
	assert_true(fresh_avatar.health.is_bleeding, "출혈 상태가 복원되어야 한다")
	assert_eq(fresh_avatar.injury.body_part, &"leg", "동일한 부위가 복원되어야 한다")
	assert_eq(fresh_avatar.injury.injury_kind, &"laceration", "동일한 부상 상태가 복원되어야 한다")
	assert_almost_eq(fresh_avatar.health.current_health, saved_health, 3.0, "체력이 복원되어야 한다")
	assert_almost_eq(fresh_avatar.stats.temperature, 72.0, 0.01, "체온이 복원되어야 한다")
	assert_almost_eq(fresh_avatar.stats.water, 61.0, 0.01, "수분이 복원되어야 한다")
	assert_almost_eq(fresh_avatar.stats.food, 53.0, 0.01, "포만이 복원되어야 한다")
	assert_almost_eq(fresh_avatar.stats.fatigue, 44.0, 2.0, "피로가 복원되어야 한다")
	assert_almost_eq(fresh_avatar.global_position.x, 400.0, 8.0, "위치가 복원되어야 한다")
	assert_almost_eq(fresh_avatar.global_position.y, 300.0, 8.0, "위치가 복원되어야 한다")

	# 클라이언트 복제본에도 인벤토리가 도착해야 한다.
	assert_true(await wait_until(func() -> bool:
		var replica: Player = _avatar_on(client, client_id)
		return replica != null and replica.inventory.count_of(&"stone") == 5, 5.0),
		"복원된 인벤토리가 클라이언트로 복제되어야 한다")
	var replica: Player = _avatar_on(client, client_id)
	assert_true(replica.injury.has_leg_laceration(), "열상이 클라이언트 복제본에도 복원되어야 한다")
	assert_almost_eq(replica.stats.temperature, 72.0, 0.01, "체온이 클라이언트로 복제되어야 한다")
	assert_almost_eq(replica.stats.water, 61.0, 0.01, "수분이 클라이언트로 복제되어야 한다")
	assert_almost_eq(replica.stats.food, 53.0, 0.01, "포만이 클라이언트로 복제되어야 한다")
	assert_almost_eq(replica.stats.fatigue, 44.0, 2.0, "피로가 클라이언트로 복제되어야 한다")


## 슬롯 만료(120초) 뒤 복귀는 새 플레이어다 — 보관 상태를 복원하지 않는다 (설계서 6.3).
func test_expired_slot_returns_as_new_player_without_state() -> void:
	var client_id: StringName = await _join_and_spawn()
	var authority_avatar: Player = _avatar_on(host, client_id)
	authority_avatar.inventory.add_item(&"stone", 5)

	client.session.leave_session()
	assert_true(await wait_until(func() -> bool:
		return host.session.get_players().size() == 1, 5.0), "호스트가 이탈을 관측해야 한다")
	host.net_move._tick_pending_despawns(31.0)  # 아바타 제거 (30초 유예 경과)
	host.session.tick_reconnect_slots(121.0)  # 슬롯 만료 (120초 경과)
	assert_false(host.session.has_reconnect_slot(client_id), "만료된 슬롯은 사라져야 한다")

	var reconnected_count: Array = [0]
	host.session.player_reconnected.connect(
		func(_player_id: StringName) -> void: reconnected_count[0] += 1)
	_rejoin(client_id)
	await wait_for_signal(host.session.player_joined, 5.0, "만료 후 복귀는 새 참가로 관측된다")
	assert_eq(reconnected_count[0], 0, "만료 후 복귀는 재접속이 아니다")
	assert_true(await wait_until(func() -> bool:
		return _avatar_on(host, client_id) != null, 5.0), "새 플레이어로 스폰되어야 한다")
	await wait_physics_frames(30)  # 잘못된 뒤늦은 복원이 없는지 안정화 후 판정

	assert_eq(_avatar_on(host, client_id).inventory.count_of(&"stone"), 0,
		"만료 후 복귀한 새 플레이어에게 옛 상태를 복원하면 안 된다")


## 재접속한 피어의 의도 RPC 가 다시 동작해야 한다 — 줍기·부상 확정 (RpcGuard 재등록).
func test_reconnected_peer_intents_work_again() -> void:
	var client_id: StringName = await _join_and_spawn()

	client.session.leave_session()
	assert_true(await wait_until(func() -> bool:
		return host.session.get_players().size() == 1, 5.0), "호스트가 이탈을 관측해야 한다")
	_rejoin(client_id)
	await wait_for_signal(host.session.player_reconnected, 5.0, "재접속으로 관측되어야 한다")
	assert_true(await wait_until(func() -> bool:
		return _avatar_on(client, client_id) != null, 5.0), "클라이언트 아바타가 다시 스폰되어야 한다")
	var replica: Player = _avatar_on(client, client_id)
	var authority_avatar: Player = _avatar_on(host, client_id)

	# 재접속 후 줍기 의도 — 호스트가 확정·복제해야 한다.
	for side: Dictionary in [host, client]:
		var item: WorldItem = WorldItemScene.instantiate()
		item.name = "Stone"
		item.item_id = &"stone"
		item.count = 2
		item.position = authority_avatar.global_position + Vector2(24.0, 0.0)
		(side.items as Node2D).add_child(item)
	await wait_physics_frames(2)
	((client.items as Node2D).get_node("Stone") as WorldItem).interact(replica)
	assert_true(await wait_until(func() -> bool:
		return authority_avatar.inventory.count_of(&"stone") == 2, 5.0),
		"재접속한 피어의 줍기 의도가 다시 동작해야 한다 (RpcGuard 재등록)")

	# 재접속 후 부상 의도 — 호스트가 클램프해 확정해야 한다.
	(client.survival as NetSurvival).request_hurt_for(replica, 10.0)
	assert_true(await wait_until(func() -> bool:
		return authority_avatar.health.is_bleeding, 5.0),
		"재접속한 피어의 부상 의도가 다시 동작해야 한다 (RpcGuard 재등록)")

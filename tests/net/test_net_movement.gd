extends GutTest

## NetMovement — 2인 이동 동기화 + 호스트 권한 검증 (설계서 7.2/7.4).
## 실제 ENet 루프백 브랜치 2개(호스트 기계/클라이언트 기계)로 검증한다.
## 클라이언트 아바타 이동은 위치 직접 설정으로 시뮬레이션한다 — 예측 이동이든
## 변조든 NetMovement 는 아바타의 현재 위치를 의도로 전송하기 때문이다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const PORT: int = 8912
const STEAM_PLAYER_ID: StringName = &"76561198000000001"

var host: Dictionary
var client: Dictionary


func before_each() -> void:
	host = _make_side("HostSide")
	client = _make_side("ClientSide")


func after_each() -> void:
	client.session.leave_session()
	host.session.leave_session()
	get_tree().set_multiplayer(null, host.root.get_path())
	get_tree().set_multiplayer(null, client.root.get_path())


## 한쪽 '기계'를 만든다: 세션 + 호스트 아바타 + 스폰 컨테이너 + NetMovement.
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

	var net: NetMovement = NetMovement.new()
	net.name = "NetMovement"
	net.session_path = ^"../NetSession"
	net.host_player_path = ^"../Player"
	net.players_container_path = ^"../Players"
	net.avatar_scene = PlayerScene
	net.config = session.config
	root.add_child(net)

	return {root = root, session = session, host_player = host_player, container = container, net = net}


func _join_and_spawn(player_id: StringName = &"") -> StringName:
	assert_eq(host.session.host_session(), OK)
	var invite: Variant = "127.0.0.1:%d" % PORT
	if not String(player_id).is_empty():
		invite = {
			address = "127.0.0.1",
			port = PORT,
			player_id = player_id,
			host_build_number = "dev",
		}
	assert_eq(client.session.join_session(invite), OK)
	await wait_for_signal(host.session.player_joined, 5.0, "호스트가 참가를 관측해야 한다")
	var client_id: StringName = client.session.get_local_player_id()
	assert_true(await wait_until(func() -> bool:
		return host.container.has_node(NodePath(String(client_id))) \
			and client.container.has_node(NodePath(String(client_id))), 5.0),
		"양쪽에 클라이언트 아바타가 스폰되어야 한다")
	return client_id


func test_join_spawns_client_avatar_on_both_sides() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	var client_side_avatar: Player = client.container.get_node(String(client_id))
	assert_not_null(host_side_avatar)
	assert_not_null(client_side_avatar)
	# 클라이언트 기계에서만 자기 아바타를 조종한다.
	var client_peer: int = client.session.get_peer_for_player(client_id)
	assert_eq(client_side_avatar.controller_peer_id, client_peer)
	assert_eq(host_side_avatar.controller_peer_id, client_peer)
	# 스폰 위치는 호스트가 정한다 (권위 스폰).
	assert_almost_eq(host_side_avatar.global_position,
		host.host_player.global_position + host.net.config.client_spawn_offset, Vector2(1.0, 1.0))


func test_client_movement_within_budget_replicates_to_host() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_side_avatar: Player = client.container.get_node(String(client_id))
	var host_side_avatar: Player = host.container.get_node(String(client_id))

	# 정직한 걷기: 물리 틱마다 3px 씩 40틱 = 120px.
	for i: int in range(40):
		client_side_avatar.global_position.x += 3.0
		await wait_physics_frames(1)
	var target_x: float = client_side_avatar.global_position.x

	assert_true(await wait_until(func() -> bool:
		return absf(host_side_avatar.global_position.x - target_x) < 16.0, 5.0),
		"호스트가 검증된 위치를 따라와야 한다")
	assert_almost_eq(host_side_avatar.global_position.x, target_x, 16.0)
	assert_eq(host.net.get_move_violation_count(client_id), 0)


func test_teleport_claim_is_rejected_and_client_is_corrected() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_side_avatar: Player = client.container.get_node(String(client_id))
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	var before: Vector2 = host_side_avatar.global_position

	# 변조된 클라이언트: 5000px 순간이동을 여러 프레임 연속 강제한다.
	# (1회 주입은 보정 스냅샷이 의도 전송보다 먼저 도착하면 되돌려져 비결정적이다.)
	for i: int in range(10):
		client_side_avatar.global_position = before + Vector2(5000.0, 0.0)
		await wait_physics_frames(1)
	await wait_physics_frames(20)

	# 호스트는 주장을 거부하고 직전 권위 위치를 유지한다 (설계서 7.4).
	assert_lt(host_side_avatar.global_position.distance_to(before), 100.0)
	assert_gt(host.net.get_move_violation_count(client_id), 0)

	# 클라이언트 자기 아바타는 서버 보정으로 되돌아온다.
	assert_true(await wait_until(func() -> bool:
		return client_side_avatar.global_position.distance_to(before) < 100.0, 5.0),
		"보정 스냅샷이 변조 위치를 되돌려야 한다")
	assert_lt(client_side_avatar.global_position.distance_to(before), 100.0)


func test_host_player_position_replicates_to_client() -> void:
	await _join_and_spawn()
	host.host_player.global_position = Vector2(300.0, 150.0)
	assert_true(await wait_until(func() -> bool:
		return client.host_player.global_position.distance_to(Vector2(300.0, 150.0)) < 1.0, 5.0),
		"호스트 아바타 위치가 클라이언트로 복제되어야 한다")
	assert_almost_eq(client.host_player.global_position, Vector2(300.0, 150.0), Vector2(1.0, 1.0))


func test_leave_keeps_avatar_in_place_then_removes_after_30_seconds() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	var left_position: Vector2 = host_side_avatar.global_position

	client.session.leave_session()
	await wait_for_signal(host.session.player_left, 5.0, "호스트가 이탈을 관측해야 한다")
	await wait_physics_frames(29 * 60)
	assert_true(host.container.has_node(NodePath(String(client_id))))
	assert_almost_eq(host_side_avatar.global_position, left_position, Vector2(0.1, 0.1))

	assert_true(await wait_until(func() -> bool:
		return not host.container.has_node(NodePath(String(client_id))) \
			and not client.container.has_node(NodePath(String(client_id))), 5.0),
		"30초 이탈 유예 뒤 양쪽에서 아바타가 정리되어야 한다")
	assert_false(host.container.has_node(NodePath(String(client_id))))
	assert_false(client.container.has_node(NodePath(String(client_id))))


func test_reconnect_restores_existing_avatar_state_by_player_id() -> void:
	var client_id: StringName = await _join_and_spawn(STEAM_PLAYER_ID)
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	host_side_avatar.global_position = Vector2(180.0, 44.0)
	client.session.leave_session()
	await wait_for_signal(host.session.player_left, 5.0, "호스트가 이탈을 관측해야 한다")

	client = _make_side("ReconnectClientSide")
	assert_eq(client.session.join_session({
		address = "127.0.0.1",
		port = PORT,
		player_id = STEAM_PLAYER_ID,
		host_build_number = "dev",
	}), OK)
	await wait_for_signal(host.session.player_reconnected, 5.0, "동일 PlayerId 재접속이어야 한다")

	assert_true(host.container.has_node(NodePath(String(STEAM_PLAYER_ID))))
	assert_almost_eq(host_side_avatar.global_position, Vector2(180.0, 44.0), Vector2(0.1, 0.1))
	assert_true(await wait_until(func() -> bool:
		return client.container.has_node(NodePath(String(STEAM_PLAYER_ID))), 5.0),
		"재접속 클라이언트가 기존 아바타를 다시 받아야 한다")
	var client_side_avatar: Player = client.container.get_node(String(STEAM_PLAYER_ID))
	assert_almost_eq(client_side_avatar.global_position, Vector2(180.0, 44.0), Vector2(1.0, 1.0))

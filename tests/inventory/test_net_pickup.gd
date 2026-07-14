extends GutTest

## NetPickup — 아이템 획득 호스트 권위 + 2인 동시성 (설계서 7.2/7.4).
## 실제 ENet 루프백 브랜치 2개(호스트 기계/클라이언트 기계)로 검증한다.
## 핵심 불변식: 어떤 경합에서도 아이템은 정확히 한 명만 획득하고,
## 월드에서 정확히 한 번 사라지며, 인벤토리 총합이 늘거나 줄지 않는다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")
const PORT: int = 8916

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


## 한쪽 '기계': 세션 + 호스트 아바타 + 스폰/아이템 컨테이너 + NetMovement + NetPickup.
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

	return {
		root = root, session = session, host_player = host_player,
		container = container, items = items, net_move = net_move, pickup = pickup,
	}


## 같은 씬을 양쪽이 로드한 상황: 같은 상대 경로·수량의 월드 아이템을 양쪽 기계에 만든다.
func _spawn_item_both(item_name: String, item_id: StringName, count: int, item_position: Vector2) -> void:
	for side: Dictionary in [host, client]:
		var item: WorldItem = WorldItemScene.instantiate()
		item.name = item_name
		item.item_id = item_id
		item.count = count
		item.position = item_position
		(side.items as Node2D).add_child(item)


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


func _item_on(side: Dictionary, item_name: String) -> WorldItem:
	var node: Node = (side.items as Node2D).get_node_or_null(item_name)
	if node == null or node.is_queued_for_deletion():
		return null
	return node as WorldItem


## 호스트 기계 기준 총 보유량 (호스트 인벤토리가 권위다).
func _host_side_total(item_id: StringName, client_id: StringName) -> int:
	var total: int = (host.host_player as Player).inventory.count_of(item_id)
	var client_avatar: Player = host.container.get_node_or_null(String(client_id)) as Player
	if client_avatar != null:
		total += client_avatar.inventory.count_of(item_id)
	return total


## 클라이언트가 줍는다 → 호스트가 검증·확정하고 양쪽에 복제된다.
func test_client_pickup_replicates_to_both_machines() -> void:
	var client_id: StringName = await _join_and_spawn()
	# 클라이언트 아바타 스폰 위치(호스트+64px) 옆에 아이템을 둔다.
	_spawn_item_both("Stone", &"stone", 3, Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))

	_item_on(client, "Stone").interact(client_avatar)

	assert_true(await wait_until(func() -> bool:
		return _host_side_total(&"stone", client_id) == 3, 5.0),
		"호스트가 클라이언트 획득을 확정해야 한다")
	var host_view_client: Player = host.container.get_node(String(client_id))
	assert_eq(host_view_client.inventory.count_of(&"stone"), 3, "호스트 쪽 클라이언트 인벤토리에 들어가야 한다")
	assert_true(await wait_until(func() -> bool:
		return _item_on(host, "Stone") == null and _item_on(client, "Stone") == null, 5.0),
		"아이템이 양쪽 월드에서 사라져야 한다")
	assert_true(await wait_until(func() -> bool:
		return client_avatar.inventory.count_of(&"stone") == 3, 5.0),
		"클라이언트 로컬 인벤토리 복제본도 채워져야 한다")


## ★ 같은 프레임에 두 기계가 같은 아이템을 줍는다 → 정확히 한 명만 획득 (복제 0, 소실 0).
func test_same_frame_contest_exactly_one_winner_across_machines() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_item_both("Contested", &"stone", 3, Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))

	# 같은 프레임: 호스트도 줍고 클라이언트도 줍는다.
	_item_on(host, "Contested").interact(host.host_player)
	_item_on(client, "Contested").interact(client_avatar)

	assert_true(await wait_until(func() -> bool:
		return _item_on(host, "Contested") == null and _item_on(client, "Contested") == null, 5.0),
		"아이템이 양쪽 월드에서 정확히 한 번 사라져야 한다")
	await wait_physics_frames(30)  # 뒤늦은 중복 확정이 없는지 안정화 후 판정

	var host_count: int = (host.host_player as Player).inventory.count_of(&"stone")
	var client_count_on_host: int = (host.container.get_node(String(client_id)) as Player).inventory.count_of(&"stone")
	assert_eq(host_count + client_count_on_host, 3, "총합 보존: 복제도 소실도 없어야 한다")
	assert_true(host_count == 0 or client_count_on_host == 0, "정확히 한 명만 획득해야 한다")
	# 클라이언트 기계의 복제본도 호스트 확정과 일치해야 한다.
	assert_true(await wait_until(func() -> bool:
		return client_avatar.inventory.count_of(&"stone") == client_count_on_host \
			and (client.host_player as Player).inventory.count_of(&"stone") == host_count, 5.0),
		"클라이언트 기계의 인벤토리 복제본이 호스트 확정과 일치해야 한다")


## ★ 호스트가 같은 프레임에 두 요청을 직렬 처리한다 → 두 번째는 소유권 검사로 거부.
## (뮤테이션 자가검증 1번: 호스트의 아이템 존재·수량 검사를 제거하면 이 테스트가 잡는다.)
func test_same_machine_serial_requests_only_first_wins() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_item_both("Serial", &"stone", 3, Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	var host_view_client: Player = host.container.get_node(String(client_id))
	var item: WorldItem = _item_on(host, "Serial")

	# 호스트 기계에서 같은 프레임에 두 아바타가 같은 아이템을 요청 (직렬 처리 모델).
	item.interact(host.host_player)
	item.interact(host_view_client)

	assert_eq((host.host_player as Player).inventory.count_of(&"stone"), 3, "첫 요청자만 획득한다")
	assert_eq(host_view_client.inventory.count_of(&"stone"), 0, "두 번째 요청은 빈 아이템이라 거부된다")
	assert_true(item.is_queued_for_deletion(), "아이템은 정확히 한 번 사라진다")


## 변조 클라이언트가 사거리 밖 아이템을 주장한다 → 호스트가 거리 검증으로 거부 (설계서 7.4).
func test_pickup_beyond_validation_distance_is_rejected() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_item_both("FarStone", &"stone", 3, Vector2(2000.0, 0.0))
	await wait_physics_frames(2)

	# 정상 상호작용(겹침)으로는 불가능한 요청을 RPC 로 직접 보낸다 (변조 시뮬레이션).
	(client.pickup as NetPickup).request_pickup.rpc_id(1, "Items/FarStone")
	await wait_physics_frames(30)

	assert_eq(_host_side_total(&"stone", client_id), 0, "사거리 밖 주장은 아무것도 얻지 못한다")
	assert_not_null(_item_on(host, "FarStone"), "아이템은 호스트 월드에 남아야 한다")
	assert_not_null(_item_on(client, "FarStone"), "아이템은 클라이언트 월드에도 남아야 한다")


## 존재하지 않는 경로·탈출 경로 주장은 폐기된다 (설계서 7.4: 명시적 스키마만 허용).
func test_bogus_item_paths_are_ignored() -> void:
	var client_id: StringName = await _join_and_spawn()

	(client.pickup as NetPickup).request_pickup.rpc_id(1, "Items/Nope")
	(client.pickup as NetPickup).request_pickup.rpc_id(1, "../../Player")
	(client.pickup as NetPickup).request_pickup.rpc_id(1, "")
	await wait_physics_frames(30)

	assert_eq(_host_side_total(&"stone", client_id), 0, "가짜 경로로는 아무것도 얻지 못한다")
	assert_eq(_host_side_total(&"bandage", client_id), 0, "가짜 경로로는 아무것도 얻지 못한다")


## 인벤토리가 거의 차면 들어간 만큼만 확정되고 잔량이 양쪽에 복제된다 (복제·소실 금지).
func test_partial_pickup_replicates_remainder() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_item_both("Bandages", &"bandage", 4, Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	# 붕대 스택 상한 5, 8칸 = 용량 40. 양쪽 복제본 모두 38개로 채워 2자리만 남긴다.
	host_view_client.inventory.add_item(&"bandage", 38)
	client_avatar.inventory.add_item(&"bandage", 38)

	_item_on(client, "Bandages").interact(client_avatar)

	assert_true(await wait_until(func() -> bool:
		return host_view_client.inventory.count_of(&"bandage") == 40, 5.0),
		"호스트가 남은 2자리만 채워야 한다")
	assert_true(await wait_until(func() -> bool:
		var host_item: WorldItem = _item_on(host, "Bandages")
		var client_item: WorldItem = _item_on(client, "Bandages")
		return host_item != null and client_item != null \
			and host_item.count == 2 and client_item.count == 2, 5.0),
		"잔량 2개가 양쪽 월드에 남아야 한다")
	assert_true(await wait_until(func() -> bool:
		return client_avatar.inventory.count_of(&"bandage") == 40, 5.0),
		"클라이언트 복제본도 40개로 일치해야 한다")

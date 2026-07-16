extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const NetCraftingScript = preload("res://scripts/crafting/net_crafting.gd")
const PORT: int = 8921

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

	var crafting: Node = NetCraftingScript.new()
	crafting.name = "NetCrafting"
	crafting.session_path = ^"../NetSession"
	crafting.host_player_path = ^"../Player"
	crafting.players_container_path = ^"../Players"
	root.add_child(crafting)

	return {root = root, session = session, host_player = host_player,
		container = container, crafting = crafting}

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

func test_client_quick_craft_replicates_to_both_machines() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_view_client: Player = host.container.get_node(String(client_id))
	var client_avatar: Player = client.container.get_node(String(client_id))
	host_view_client.inventory.add_item(&"raw_meat", 1)
	client_avatar.inventory.add_item(&"raw_meat", 1)

	client.crafting.request(&"craft_bait", client_avatar)

	assert_true(await wait_until(func() -> bool:
		return host_view_client.inventory.count_of(&"bait") == 1, 5.0),
		"호스트가 제작을 확정해야 한다")
	assert_true(await wait_until(func() -> bool:
		return client_avatar.inventory.count_of(&"bait") == 1 \
			and client_avatar.inventory.count_of(&"raw_meat") == 0, 5.0),
		"클라이언트 복제본도 같은 제작 결과여야 한다")

func test_material_slot_weight_fail_without_remote_mutation() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_view_client: Player = host.container.get_node(String(client_id))
	var client_avatar: Player = client.container.get_node(String(client_id))

	client.crafting.request_quick_craft.rpc_id(1, "craft_bait")
	await wait_physics_frames(30)
	assert_eq(host_view_client.inventory.count_of(&"bait"), 0, "재료 없는 요청은 거부된다")
	assert_eq(client_avatar.inventory.count_of(&"bait"), 0, "거부는 복제되지 않는다")

	host_view_client.inventory.max_weight = 0.25
	client_avatar.inventory.max_weight = 0.25
	client.crafting.request_quick_craft.rpc_id(1, "craft_bait")
	await wait_physics_frames(30)
	assert_eq(host_view_client.inventory.count_of(&"bait"), 0, "무게 부족도 거부된다")

	host_view_client.inventory.max_weight = 400.0
	client_avatar.inventory.max_weight = 400.0
	assert_eq(host_view_client.inventory.add_item(&"stone", 300), 300)
	assert_eq(client_avatar.inventory.add_item(&"stone", 300), 300)
	assert_eq(host_view_client.inventory.add_item(&"raw_meat", 2), 2)
	assert_eq(client_avatar.inventory.add_item(&"raw_meat", 2), 2)
	client.crafting.request_quick_craft.rpc_id(1, "craft_bait")
	await wait_physics_frames(30)
	assert_eq(host_view_client.inventory.count_of(&"raw_meat"), 2, "슬롯 부족 거부도 재료를 보존한다")
	assert_eq(host_view_client.inventory.count_of(&"bait"), 0)

func test_duplicate_requests_consume_material_exactly_once() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_view_client: Player = host.container.get_node(String(client_id))
	var client_avatar: Player = client.container.get_node(String(client_id))
	host_view_client.inventory.add_item(&"raw_meat", 1)
	client_avatar.inventory.add_item(&"raw_meat", 1)

	client.crafting.request_quick_craft.rpc_id(1, "craft_bait")
	client.crafting.request_quick_craft.rpc_id(1, "craft_bait")

	assert_true(await wait_until(func() -> bool:
		return host_view_client.inventory.count_of(&"bait") == 1, 5.0),
		"동시 중복 요청도 권위 인벤토리에서 한 번만 성공해야 한다")
	await wait_physics_frames(30)
	assert_eq(host_view_client.inventory.count_of(&"raw_meat"), 0)
	assert_eq(host_view_client.inventory.count_of(&"bait"), 1)
	assert_true(await wait_until(func() -> bool:
		return client_avatar.inventory.count_of(&"bait") == 1, 5.0),
		"확정은 클라이언트에 한 번만 복제된다")

func test_client_payload_cannot_supply_result_or_count() -> void:
	var client_id: StringName = await _join_and_spawn()
	var host_view_client: Player = host.container.get_node(String(client_id))
	host_view_client.inventory.add_item(&"raw_meat", 1)

	client.crafting.request_quick_craft.rpc_id(1, "craft_bait")
	assert_true(await wait_until(func() -> bool:
		return host_view_client.inventory.count_of(&"bait") == 1, 5.0),
		"페이로드는 recipe_id 뿐이라 결과/수량을 주입할 수 없다")
	assert_eq(host_view_client.inventory.count_of(&"bait"), 1)

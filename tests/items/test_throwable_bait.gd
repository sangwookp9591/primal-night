extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const NetPickupScript = preload("res://scripts/items/net_pickup.gd")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")
const ThrowProfile: NoiseProfile = preload("res://data/senses/noise_throw.tres")

var _event_bus: Node = null


func before_each() -> void:
	_event_bus = get_node("/root/EventBus")


func _make_config() -> SmellGridConfig:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	config.tick_interval = 0.25
	config.decay_factor = 1.0
	config.advect_fraction = 0.0
	config.min_active_value = 0.5
	return config


func _make_side() -> Dictionary:
	var root: Node = add_child_autofree(Node.new())
	root.name = "HostSide"

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

	var grid: SmellGrid = SmellGridScript.new()
	grid.name = "SmellGrid"
	grid.config = _make_config()
	grid.area_origin = Vector2.ZERO
	grid.area_size = Vector2(1000.0, 1000.0)
	root.add_child(grid)

	var pickup: NetPickup = NetPickupScript.new()
	pickup.name = "NetPickup"
	pickup.session_path = ^"../NetSession"
	pickup.host_player_path = ^"../Player"
	pickup.players_container_path = ^"../Players"
	pickup.world_root_path = ^".."
	root.add_child(pickup)

	return { root = root, session = session, player = player, grid = grid, pickup = pickup }


func test_throw_request_protocol_does_not_accept_client_claimed_quantity() -> void:
	var pickup: NetPickup = NetPickupScript.new()
	var request_arg_count: int = -1
	for method: Dictionary in pickup.get_method_list():
		if method.name == "request_throw_bait":
			request_arg_count = (method.args as Array).size()
			break
	pickup.free()

	assert_eq(request_arg_count, 1, "클라이언트 투척 RPC 는 목표 좌표만 받고 수량 주장은 받지 않아야 한다")


func test_host_throw_consumes_bait_and_creates_noise_and_smell_source() -> void:
	var side: Dictionary = _make_side()
	var player: Player = side.player
	player.global_position = Vector2(200.0, 200.0)
	assert_eq(player.inventory.add_item(&"bait", 2), 2, "전제: 미끼 아이템 데이터가 등록되어야 한다")
	watch_signals(_event_bus)

	(side.pickup as NetPickup).request_throw_bait_for(player, Vector2(320.0, 220.0))
	await wait_physics_frames(1)

	assert_eq(player.inventory.count_of(&"bait"), 1, "투척이 확정되면 미끼 1개만 소비해야 한다")
	var thrown: Node = (side.root as Node).get_node_or_null("ThrownBaits")
	assert_not_null(thrown, "투척 지점 컨테이너가 생성되어야 한다")
	assert_eq(thrown.get_child_count(), 1, "착지한 미끼 노드가 1개 생성되어야 한다")
	assert_eq((thrown.get_child(0) as Node2D).global_position, Vector2(320.0, 220.0))
	assert_signal_emitted(_event_bus, "noise_emitted")
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[0], Vector2(320.0, 220.0), "착지 소리는 목표 지점에서 나야 한다")
	assert_eq(params[1], ThrowProfile.radius, "noise_throw 프로필 반경을 재사용해야 한다")
	assert_eq((side.grid as SmellGrid).get_registered_smell_source_count(), 1,
		"착지 미끼는 등록형 냄새 원천이어야 한다")

	(side.grid as SmellGrid)._process(0.5)
	assert_gt((side.grid as SmellGrid).get_smell_at(Vector2(320.0, 220.0)), 0.0,
		"등록된 미끼 위치에서 지속 냄새가 나야 한다")


func test_throw_without_bait_is_rejected() -> void:
	var side: Dictionary = _make_side()
	var player: Player = side.player
	player.global_position = Vector2(200.0, 200.0)
	watch_signals(_event_bus)

	(side.pickup as NetPickup).request_throw_bait_for(player, Vector2(260.0, 200.0))
	await wait_physics_frames(1)

	assert_null((side.root as Node).get_node_or_null("ThrownBaits"), "보유 미끼가 없으면 월드에 생성하지 않는다")
	assert_signal_not_emitted(_event_bus, "noise_emitted")
	assert_eq((side.grid as SmellGrid).get_registered_smell_source_count(), 0)


func test_throw_beyond_host_validation_distance_is_rejected() -> void:
	var side: Dictionary = _make_side()
	var player: Player = side.player
	player.global_position = Vector2(200.0, 200.0)
	assert_eq(player.inventory.add_item(&"bait", 1), 1)
	watch_signals(_event_bus)

	(side.pickup as NetPickup).request_throw_bait_for(player, Vector2(900.0, 200.0))
	await wait_physics_frames(1)

	assert_eq(player.inventory.count_of(&"bait"), 1, "사거리 밖 투척 주장은 인벤토리를 소비하지 않는다")
	assert_null((side.root as Node).get_node_or_null("ThrownBaits"))
	assert_signal_not_emitted(_event_bus, "noise_emitted")

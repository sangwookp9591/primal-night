extends GutTest

## NetCampfire — 모닥불 설치·점화 호스트 권위 + 복제 (설계서 5.8, 7.2/7.4, W2-T5).
## 실제 ENet 루프백 브랜치 2개(호스트 기계/클라이언트 기계)로 검증한다.
## 핵심 불변식:
##   1. 설치 확정·campfire_lit 발신은 호스트에서만 일어난다 (랩터 AI 는 호스트 소유).
##   2. 같은 지정자리 동시 설치는 정확히 하나만 생기고 재료도 한 번만 소비된다.
##   3. 재료·거리 검증은 호스트가 한다 — 변조 RPC 로는 지을 수 없다.
##   4. 연료 소진 타이머는 호스트 소유 — 클라이언트는 소등 결과만 복제받는다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CampfireSiteScene: PackedScene = preload("res://scenes/props/campfire_site.tscn")
const CampfireConfigScript = preload("res://scripts/props/campfire_config.gd")
const PORT: int = 8918

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


## 한쪽 '기계': 세션 + 호스트 아바타 + 스폰 컨테이너 + NetMovement + NetCampfire.
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

	var props: Node2D = Node2D.new()
	props.name = "Props"
	root.add_child(props)

	var net_move: NetMovement = NetMovement.new()
	net_move.name = "NetMovement"
	net_move.session_path = ^"../NetSession"
	net_move.host_player_path = ^"../Player"
	net_move.players_container_path = ^"../Players"
	net_move.avatar_scene = PlayerScene
	net_move.config = session.config
	root.add_child(net_move)

	var campfire_net: NetCampfire = NetCampfire.new()
	campfire_net.name = "NetCampfire"
	campfire_net.session_path = ^"../NetSession"
	campfire_net.host_player_path = ^"../Player"
	campfire_net.players_container_path = ^"../Players"
	campfire_net.world_root_path = ^".."
	root.add_child(campfire_net)

	return {
		root = root, session = session, host_player = host_player,
		container = container, props = props, campfire_net = campfire_net,
	}


func _make_config() -> CampfireConfig:
	var config: CampfireConfig = CampfireConfigScript.new()
	config.light_radius = 220.0
	config.fuel_seconds = 10.0
	config.stone_cost = 3
	config.wood_cost = 2
	config.build_seconds = 1.0
	return config


## 같은 씬을 양쪽이 로드한 상황: 같은 상대 경로·설정의 지정자리를 양쪽 기계에 만든다.
func _spawn_site_both(site_name: String, site_position: Vector2) -> void:
	for side: Dictionary in [host, client]:
		var site: CampfireSite = CampfireSiteScene.instantiate()
		site.name = site_name
		site.config = _make_config()
		site.position = site_position
		(side.props as Node2D).add_child(site)


func _site_on(side: Dictionary, site_name: String = "Site") -> CampfireSite:
	return (side.props as Node2D).get_node(site_name) as CampfireSite


func _stock(player: Player) -> void:
	player.inventory.add_item(&"stone", 3)
	player.inventory.add_item(&"wood", 2)


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


func _both_sites_lit(site_name: String = "Site") -> bool:
	var host_site: CampfireSite = _site_on(host, site_name)
	var client_site: CampfireSite = _site_on(client, site_name)
	return host_site.campfire != null and host_site.campfire.is_lit \
		and client_site.campfire != null and client_site.campfire.is_lit


## 클라이언트가 설치 홀드를 완료한다 → 호스트가 재료·거리·자리를 검증해 확정하고
## 양쪽에 복제된다. campfire_lit 은 호스트에서만 정확히 1회 발신된다.
func test_client_build_replicates_to_both_machines() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_site_both("Site", Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	# 프로덕션에선 획득 복제로 권위 인벤토리와 복제본이 일치한다 — 그 상태를 재현.
	_stock(host_view_client)
	_stock(client_avatar)
	watch_signals(_event_bus)

	_site_on(client).interact(client_avatar)

	assert_true(await wait_until(_both_sites_lit, 5.0),
		"모닥불이 양쪽 기계에 설치·점화되어야 한다")
	assert_eq(host_view_client.inventory.count_of(&"stone"), 0, "호스트가 권위적으로 돌을 소비한다")
	assert_eq(host_view_client.inventory.count_of(&"wood"), 0, "호스트가 권위적으로 나무를 소비한다")
	assert_true(await wait_until(func() -> bool:
		return client_avatar.inventory.count_of(&"stone") == 0 \
			and client_avatar.inventory.count_of(&"wood") == 0, 5.0),
		"재료 소비가 클라이언트 복제본에도 반영되어야 한다")
	assert_eq(get_signal_emit_count(_event_bus, "campfire_lit"), 1,
		"campfire_lit 은 호스트에서만 1회 — 클라이언트도 발신하면 랩터가 불을 2개로 인식한다")


## ★ 같은 프레임에 두 명이 같은 지정자리에 설치를 시도한다 → 정확히 하나만 생기고
## 재료는 정확히 한 명 몫만 소비된다 (아이템 동시 획득과 같은 경합 문제).
func test_same_frame_contest_exactly_one_campfire_single_material_spend() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_site_both("Site", Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	_stock(host.host_player)
	_stock(client.host_player)  # 호스트 인벤토리의 클라이언트 쪽 복제본
	_stock(host_view_client)
	_stock(client_avatar)
	watch_signals(_event_bus)

	# 같은 프레임: 호스트도 짓고 클라이언트도 짓는다.
	_site_on(host).interact(host.host_player)
	_site_on(client).interact(client_avatar)

	assert_true(await wait_until(_both_sites_lit, 5.0),
		"모닥불이 양쪽 기계에 정확히 하나 생겨야 한다")
	await wait_physics_frames(30)  # 뒤늦은 중복 확정이 없는지 안정화 후 판정

	var host_stone: int = (host.host_player as Player).inventory.count_of(&"stone")
	var client_stone_on_host: int = host_view_client.inventory.count_of(&"stone")
	assert_eq(host_stone + client_stone_on_host, 3, "재료 총합 보존: 정확히 한 명 몫만 소비")
	assert_true(host_stone == 0 or client_stone_on_host == 0, "정확히 한 명만 재료를 소비한다")
	assert_true(await wait_until(func() -> bool:
		return (client.host_player as Player).inventory.count_of(&"stone") == host_stone \
			and client_avatar.inventory.count_of(&"stone") == client_stone_on_host, 5.0),
		"클라이언트 기계의 인벤토리 복제본이 호스트 확정과 일치해야 한다")
	assert_eq(get_signal_emit_count(_event_bus, "campfire_lit"), 1,
		"경합에서도 campfire_lit 은 정확히 1회 (호스트 단독)")


## 변조 클라이언트가 재료 없이 설치 RPC 를 직접 보낸다 → 호스트가 재료 검증으로 거부.
## (뮤테이션 자가검증 2번: 호스트의 재료 검증을 제거하면 이 테스트가 잡는다.)
func test_build_without_materials_is_rejected_then_control_build_succeeds() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_site_both("Site", Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))

	# 재료 없이 정상 상호작용으로는 불가능한 요청을 RPC 로 직접 보낸다 (변조 시뮬레이션).
	(client.campfire_net as NetCampfire).request_campfire_build.rpc_id(1, "Props/Site")
	await wait_physics_frames(30)

	assert_null(_site_on(host).campfire, "재료 없는 변조 설치 주장은 거부되어야 한다")
	assert_null(_site_on(client).campfire, "거부된 설치는 클라이언트에도 복제되지 않는다")

	# 대조군: 같은 RPC 가 재료만 있으면 성공한다 — 거부가 파이프 고장이 아님을 증명.
	_stock(host_view_client)
	_stock(client_avatar)
	(client.campfire_net as NetCampfire).request_campfire_build.rpc_id(1, "Props/Site")
	assert_true(await wait_until(_both_sites_lit, 5.0),
		"재료가 있으면 같은 RPC 로 설치가 확정·복제되어야 한다")
	assert_eq(host_view_client.inventory.count_of(&"stone"), 0, "대조군 설치가 재료를 소비한다")


## 변조 클라이언트가 사거리 밖 지정자리를 주장한다 → 호스트가 거리 검증으로 거부.
func test_build_beyond_distance_is_rejected() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_site_both("FarSite", Vector2(2000.0, 0.0))
	_spawn_site_both("NearSite", Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	_stock(host_view_client)
	_stock(client_avatar)

	(client.campfire_net as NetCampfire).request_campfire_build.rpc_id(1, "Props/FarSite")
	await wait_physics_frames(30)

	assert_null(_site_on(host, "FarSite").campfire, "사거리 밖 설치 주장은 거부되어야 한다")
	assert_eq(host_view_client.inventory.count_of(&"stone"), 3, "거부 시 재료는 보존된다")

	# 대조군: 가까운 자리는 같은 경로로 성공한다.
	(client.campfire_net as NetCampfire).request_campfire_build.rpc_id(1, "Props/NearSite")
	assert_true(await wait_until(func() -> bool: return _both_sites_lit("NearSite"), 5.0),
		"사거리 안 자리는 설치가 확정·복제되어야 한다")


## 연료 소진 타이머는 호스트 소유다. 클라이언트 모닥불은 스스로 타지 않고
## 소등 결과만 복제받는다. campfire_extinguished 도 호스트에서만 1회.
func test_fuel_timer_is_host_owned_and_extinguish_replicates() -> void:
	await _join_and_spawn()
	_spawn_site_both("Site", Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	_stock(host.host_player)
	_stock(client.host_player)

	_site_on(host).interact(host.host_player)
	assert_true(await wait_until(_both_sites_lit, 5.0), "호스트 설치가 양쪽에 복제되어야 한다")

	var host_fire: Campfire = _site_on(host).campfire
	var client_fire: Campfire = _site_on(client).campfire
	var client_fuel_before: float = client_fire.fuel_remaining
	await wait_physics_frames(30)
	assert_lt(host_fire.fuel_remaining, 10.0, "호스트 연료는 시간에 따라 줄어야 한다")
	assert_eq(client_fire.fuel_remaining, client_fuel_before,
		"클라이언트는 연료 타이머를 돌리지 않는다 (호스트 소유)")

	watch_signals(_event_bus)
	host_fire.fuel_remaining = 0.05
	assert_true(await wait_until(func() -> bool: return not host_fire.is_lit, 5.0),
		"호스트 모닥불이 연료 소진으로 꺼져야 한다")
	assert_true(await wait_until(func() -> bool: return not client_fire.is_lit, 5.0),
		"소등이 클라이언트로 복제되어야 한다")
	assert_eq(get_signal_emit_count(_event_bus, "campfire_extinguished"), 1,
		"campfire_extinguished 도 호스트에서만 1회")


func test_client_cook_hold_is_host_validated_and_replicated() -> void:
	var client_id := await _join_and_spawn()
	_spawn_site_both("Site", Vector2(32.0, 0.0))
	await wait_physics_frames(2)
	# 설치 과정과 독립적으로 굽기 프로토콜만 검증한다.
	_site_on(host).build_and_light()
	_site_on(client).build_and_light()
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	client_avatar.inventory.add_item(&"raw_meat", 1)
	host_view_client.inventory.add_item(&"raw_meat", 1)

	_site_on(client).on_hold_started(client_avatar)
	assert_true(await wait_until(func() -> bool: return _site_on(host).has_cooking_smell(), 2.0),
		"클라이언트 홀드 시작은 호스트의 요리 냄새 원천을 연다")
	await wait_seconds(CampfireSite.COOK_SECONDS)
	_site_on(client).interact(client_avatar)
	_site_on(client).on_hold_ended(client_avatar)

	assert_true(await wait_until(func() -> bool:
		return host_view_client.inventory.count_of(&"cooked_meat") == 1 \
			and client_avatar.inventory.count_of(&"cooked_meat") == 1, 5.0),
		"호스트 확정한 날고기→구운 고기 변환이 양쪽 인벤토리에 복제된다")
	assert_eq(host_view_client.inventory.count_of(&"raw_meat"), 0)
	assert_eq(client_avatar.inventory.count_of(&"raw_meat"), 0)

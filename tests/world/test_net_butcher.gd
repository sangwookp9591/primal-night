extends GutTest

## NetButcher — 해체 산출 호스트 권위 (W5-T2, 정본 §14.4).
##
## 핵심 불변식: 구간 bit 는 **정확히 한 번만** 확정된다. 재접속·동시 해체·즉시 커밋
## 변조 어느 경로로도 같은 bit 를 두 번 지급하지 않고, 지급에 실패하면 bit 를 남긴다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")

const STONE_KNIFE: StringName = &"stone_knife"

var _port: int = 0
var host: Dictionary
var client: Dictionary


func before_each() -> void:
	_port = NetTestPorts.pick_available_port(0)
	host = _make_side("HostSide")
	client = _make_side("ClientSide")


func after_each() -> void:
	client.session.leave_session()
	host.session.leave_session()
	get_tree().set_multiplayer(null, host.root.get_path())
	get_tree().set_multiplayer(null, client.root.get_path())


## 한쪽 '기계': 세션 + 호스트 아바타 + 사체 컨테이너 + NetMovement + NetButcher.
func _make_side(side_name: String) -> Dictionary:
	var root: Node = add_child_autofree(Node.new())
	root.name = side_name
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())

	var session: LocalSessionService = LocalSessionService.new()
	session.name = "NetSession"
	session.config = NetConfig.new()
	session.config.port = _port
	root.add_child(session)

	var host_player: Player = PlayerScene.instantiate()
	host_player.name = "Player"
	root.add_child(host_player)

	var container: Node2D = Node2D.new()
	container.name = "Players"
	root.add_child(container)

	var carcasses: Node2D = Node2D.new()
	carcasses.name = "Carcasses"
	root.add_child(carcasses)

	var net_move: NetMovement = NetMovement.new()
	net_move.name = "NetMovement"
	net_move.session_path = ^"../NetSession"
	net_move.host_player_path = ^"../Player"
	net_move.players_container_path = ^"../Players"
	net_move.avatar_scene = PlayerScene
	net_move.config = session.config
	root.add_child(net_move)

	var butcher: NetButcher = NetButcher.new()
	butcher.name = "NetButcher"
	butcher.session_path = ^"../NetSession"
	butcher.host_player_path = ^"../Player"
	butcher.players_container_path = ^"../Players"
	butcher.world_root_path = ^".."
	root.add_child(butcher)

	return {
		root = root, session = session, host_player = host_player,
		container = container, carcasses = carcasses, net_move = net_move, butcher = butcher,
	}


## 홀드 시간을 짧게 줄인 프로필. 실시간 8초를 기다리면 테스트가 분 단위가 된다.
##
## .tres 를 그대로 쓰지 않는 이유: preload/ExtResource 는 Resource 인스턴스를 캐시하므로
## 양쪽 기계의 Carcass 가 **같은 프로필 객체**를 공유한다 — 거기서 값을 고치면 다른
## 테스트까지 오염된다. 그래서 기계마다 duplicate 를 준다.
## 반드시 NetButcher.BUTCHER_HOLD_SLACK_SECONDS 보다 넉넉히 길어야 한다.
## 슬랙보다 짧으면 `elapsed < required - slack` 이 영원히 거짓이라 홀드 검증이
## 공회전하고, 즉시 커밋 변조 테스트가 통과하는 척만 한다.
func _fast_profile() -> CarcassProfile:
	var profile: CarcassProfile = load("res://data/creatures/carcass_raptor.tres").duplicate()
	profile.base_butcher_seconds = 1.0
	assert_gt(profile.base_butcher_seconds, NetButcher.BUTCHER_HOLD_SLACK_SECONDS * 2.0,
		"빠른 프로필이 슬랙보다 짧으면 홀드 검증을 실제로 시험하지 못한다")
	return profile


## 같은 씬을 양쪽이 로드한 상황: 같은 상대 경로의 사체를 양쪽 기계에 만든다.
## 프로필은 _ready 가 읽으므로 트리에 넣기 전에 갈아 끼운다.
func _spawn_carcass_both(carcass_name: String, at: Vector2) -> void:
	for side: Dictionary in [host, client]:
		var carcass: Carcass = CarcassScene.instantiate()
		carcass.name = carcass_name
		carcass.position = at
		carcass.profile = _fast_profile()
		(side.carcasses as Node2D).add_child(carcass)


func _join_and_spawn() -> StringName:
	assert_eq(host.session.host_session(), OK)
	assert_eq(client.session.join_session("127.0.0.1:%d" % _port), OK)
	await wait_for_signal(host.session.player_joined, 5.0, "호스트가 참가를 관측해야 한다")
	var client_id: StringName = client.session.get_local_player_id()
	assert_true(await wait_until(func() -> bool:
		return host.container.has_node(NodePath(String(client_id))) \
			and client.container.has_node(NodePath(String(client_id))), 5.0),
		"양쪽에 클라이언트 아바타가 스폰되어야 한다")
	return client_id


## 넷 스택 밖(테스트 루트 아래)의 사체 — Carcass 가 NetButcher 를 찾지 못해
## 로컬 경로로 떨어진다. owns() 가 false 라 host/client 의 NetButcher 를 잡지 않는다.
func _make_local_carcass() -> Carcass:
	var carcass: Carcass = CarcassScene.instantiate()
	carcass.profile = _fast_profile()
	return add_child_autofree(carcass)


func _carcass_on(side: Dictionary, carcass_name: String) -> Carcass:
	return (side.carcasses as Node2D).get_node_or_null(carcass_name) as Carcass


## 홀드를 실제로 채운 뒤 커밋한다 — 호스트 시계 검증을 정직하게 통과시킨다.
## 지름길(테스트 전용 시드)을 두지 않는 이유는 그 시드가 곧 변조 경로이기 때문이다.
func _butcher_one_stage(carcass: Carcass, who: Player) -> void:
	carcass.on_hold_started(who)
	await wait_physics_frames(75)
	carcass.interact(who)
	carcass.on_hold_ended(who)


# --- 로컬(단일 기계) 권위 규칙 ------------------------------------------------

func test_each_stage_sets_exactly_one_bit_in_order() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var carcass: Carcass = _make_local_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)

	assert_eq(carcass.yield_mask, 0, "전제: 손대지 않은 사체는 mask 0")
	for stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.apply_stage(player), "구간 %d 확정" % stage)
		assert_eq(carcass.yield_mask & (1 << stage), 1 << stage, "구간 %d bit 가 서야 한다" % stage)
		assert_eq(carcass.stages_done(), stage + 1, "구간은 순서대로 하나씩 선다")

	assert_eq(carcass.yield_mask, (1 << carcass.profile.stage_count) - 1, "4구간이면 mask 가 가득 찬다")


func test_fully_butchered_carcass_refuses_further_stages() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var carcass: Carcass = _make_local_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	for stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.apply_stage(player))
	var mask_after_full: int = carcass.yield_mask
	var meat_after_full: int = player.inventory.count_of(&"raw_meat")

	assert_false(carcass.apply_stage(player), "골격에서 더 확정할 구간은 없다")

	assert_eq(carcass.yield_mask, mask_after_full, "거부된 시도가 mask 를 바꾸면 안 된다")
	assert_eq(player.inventory.count_of(&"raw_meat"), meat_after_full, "거부된 시도로 산출이 늘면 안 된다")


func test_full_butcher_yields_exactly_one_bone_scraper_worth_of_materials() -> void:
	# 정본 §14.4: 보상은 고기보다 "가죽·힘줄·뼈의 선택권". 해체가 다음 해체를
	# 25% 빠르게 만드는 고리가 성립해야 한다.
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var carcass: Carcass = _make_local_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)

	for stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.apply_stage(player))

	var recipe: RecipeData = get_node("/root/GameData").get_recipe(&"craft_bone_scraper")
	assert_not_null(recipe, "전제: 뼈 긁개 레시피가 등록돼 있다")
	for item_id: StringName in recipe.ingredients:
		assert_true(player.inventory.has_item(item_id, int(recipe.ingredients[item_id])),
			"완전 해체 산출로 뼈 긁개 재료 %s 를 채울 수 있어야 한다" % item_id)


## 정본 §14.4 + 계획 §6: 만석 때 bit 를 소모하면 산출이 조용히 증발한다.
func test_full_inventory_fails_the_stage_without_burning_the_bit() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var carcass: Carcass = _make_local_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	# 무게 상한까지 채운다 — 첫 구간 산출(날고기 2 = 2.0kg)이 들어갈 자리가 없다.
	var meat: ItemData = get_node("/root/GameData").get_item(&"raw_meat")
	var room: int = int((player.inventory.max_weight - player.inventory.total_weight()) / meat.weight)
	assert_eq(player.inventory.add_item(&"raw_meat", room), room, "전제: 무게를 상한까지 채운다")

	assert_false(carcass.apply_stage(player), "산출이 안 들어가면 구간은 실패한다")

	assert_eq(carcass.yield_mask, 0, "실패한 구간은 bit 를 소모하지 않는다")
	assert_eq(carcass.stages_done(), 0, "실패한 구간은 진행으로 세지 않는다")


func test_stage_becomes_grantable_again_after_making_room() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var carcass: Carcass = _make_local_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	var meat: ItemData = get_node("/root/GameData").get_item(&"raw_meat")
	var room: int = int((player.inventory.max_weight - player.inventory.total_weight()) / meat.weight)
	assert_eq(player.inventory.add_item(&"raw_meat", room), room)
	assert_false(carcass.apply_stage(player), "전제: 만석이라 실패")

	assert_true(player.inventory.remove_item(&"raw_meat", room), "무게를 비운다")

	assert_true(carcass.apply_stage(player), "자리를 만들면 같은 구간을 다시 받을 수 있다")
	assert_eq(carcass.stages_done(), 1)


func test_partial_yield_is_never_granted() -> void:
	# 한 구간이 반만 들어가면 나머지를 다시 받을 방법이 없다 (bit 는 구간 단위).
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var carcass: Carcass = _make_local_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	var meat: ItemData = get_node("/root/GameData").get_item(&"raw_meat")
	# 날고기 1개 분량만 남기고 채운다 — 첫 구간 산출은 날고기 2다.
	var room: int = int((player.inventory.max_weight - player.inventory.total_weight()) / meat.weight)
	assert_eq(player.inventory.add_item(&"raw_meat", room - 1), room - 1)
	var before: int = player.inventory.count_of(&"raw_meat")

	assert_false(carcass.apply_stage(player), "전량이 안 들어가면 구간 실패")

	assert_eq(player.inventory.count_of(&"raw_meat"), before, "부분 지급은 하지 않는다")
	assert_eq(carcass.yield_mask, 0)


# --- 2인 ENet 호스트 권위 -----------------------------------------------------

func test_client_butcher_stage_is_confirmed_by_host_and_replicates() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_carcass_both("Carcass", Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	client_avatar.inventory.add_item(STONE_KNIFE, 1)
	host_view_client.inventory.add_item(STONE_KNIFE, 1)

	await _butcher_one_stage(_carcass_on(client, "Carcass"), client_avatar)

	assert_true(await wait_until(func() -> bool:
		return _carcass_on(host, "Carcass").stages_done() == 1, 5.0),
		"호스트가 클라이언트 해체 구간을 확정해야 한다")
	assert_eq(host_view_client.inventory.count_of(&"raw_meat"), 2,
		"호스트 쪽 클라이언트 인벤토리에 산출이 들어가야 한다")
	assert_true(await wait_until(func() -> bool:
		return _carcass_on(client, "Carcass").stages_done() == 1, 5.0),
		"클라이언트 사체 복제본도 구간이 반영돼야 한다")


## 정본 §14.4 / §15.5: 클라이언트가 즉시 완료를 주장할 수 없다.
func test_client_cannot_commit_a_stage_without_holding_long_enough() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_carcass_both("Carcass", Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	client_avatar.inventory.add_item(STONE_KNIFE, 1)
	host.container.get_node(String(client_id)).inventory.add_item(STONE_KNIFE, 1)
	var client_carcass: Carcass = _carcass_on(client, "Carcass")

	# 홀드를 시작하자마자 커밋을 주장한다 — 8초를 채우지 않았다.
	client_carcass.on_hold_started(client_avatar)
	await wait_physics_frames(2)
	client_carcass.interact(client_avatar)
	await wait_physics_frames(30)

	assert_eq(_carcass_on(host, "Carcass").stages_done(), 0,
		"홀드 시간을 채우지 않은 커밋은 호스트가 거부해야 한다")
	assert_eq(host.container.get_node(String(client_id)).inventory.count_of(&"raw_meat"), 0,
		"거부된 커밋으로 산출이 나가면 안 된다")


func test_client_cannot_commit_a_stage_it_never_started() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_carcass_both("Carcass", Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	client_avatar.inventory.add_item(STONE_KNIFE, 1)
	host.container.get_node(String(client_id)).inventory.add_item(STONE_KNIFE, 1)

	# 홀드 시작 통지 없이 커밋만 주장한다.
	_carcass_on(client, "Carcass").interact(client_avatar)
	await wait_physics_frames(30)

	assert_eq(_carcass_on(host, "Carcass").stages_done(), 0,
		"세션 없는 커밋은 호스트가 거부해야 한다")


func test_host_rejects_a_butcher_claim_from_out_of_range() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_carcass_both("Carcass", Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	client_avatar.inventory.add_item(STONE_KNIFE, 1)
	var host_view_client: Player = host.container.get_node(String(client_id))
	host_view_client.inventory.add_item(STONE_KNIFE, 1)
	var client_carcass: Carcass = _carcass_on(client, "Carcass")

	# 호스트 월드에서 아바타를 사체에서 멀리 떨어뜨린다 (클라이언트만 가까운 척).
	# NetMovement 는 마지막 unreliable 위치가 유실돼도 복구하도록 정지 중에도 최신
	# 의도를 재전송한다. 이 테스트는 해체 RPC의 위조만 격리해야 하므로 위치 동기화를
	# 멈춰, 클라이언트가 가까운 좌표를 계속 정직하게 재주장하는 상황과 섞지 않는다.
	(client.net_move as NetMovement).set_physics_process(false)
	host_view_client.global_position = Vector2(4000.0, 4000.0)
	await _butcher_one_stage(client_carcass, client_avatar)
	await wait_physics_frames(30)

	assert_eq(_carcass_on(host, "Carcass").stages_done(), 0,
		"호스트 월드 기준 사거리 밖 해체 주장은 거부해야 한다")


## 정본 §14.4: "재접속·동시 해체에서 같은 bit 두 번 지급 금지"
##
## 두 명이 각자 홀드를 채웠으면 **서로 다른 구간**을 하나씩 가져가는 게 맞다 —
## 막아야 하는 건 같은 구간 산출이 두 번 나가는 것이다. 호스트가 커밋을 직렬로
## 처리하며 next_stage() 를 다시 읽기 때문에 성립한다.
func test_concurrent_butchers_take_distinct_stages_and_never_double_pay_a_bit() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_carcass_both("Carcass", Vector2(32.0, 24.0))
	await wait_physics_frames(2)
	var client_avatar: Player = client.container.get_node(String(client_id))
	var host_view_client: Player = host.container.get_node(String(client_id))
	for who: Player in [host.host_player, client_avatar, host_view_client]:
		who.inventory.add_item(STONE_KNIFE, 1)
	var host_carcass: Carcass = _carcass_on(host, "Carcass")
	var client_carcass: Carcass = _carcass_on(client, "Carcass")

	# 양쪽이 같은 사체의 같은 구간을 동시에 주장한다.
	host_carcass.on_hold_started(host.host_player)
	client_carcass.on_hold_started(client_avatar)
	await wait_physics_frames(75)
	host_carcass.interact(host.host_player)
	client_carcass.interact(client_avatar)
	await wait_physics_frames(30)

	assert_eq(host_carcass.stages_done(), 2, "각자 홀드를 채웠으면 구간을 하나씩 가져간다")
	# 구간 0 만 날고기 2 를 준다. 같은 bit 가 두 번 지급됐다면 4 가 된다.
	var meat_total: int = (host.host_player as Player).inventory.count_of(&"raw_meat") \
		+ host_view_client.inventory.count_of(&"raw_meat")
	assert_eq(meat_total, 2, "구간 0 의 산출이 두 번 나가면 안 된다")
	# 구간 1 만 뼈 2 를 준다.
	var bone_total: int = (host.host_player as Player).inventory.count_of(&"bone") \
		+ host_view_client.inventory.count_of(&"bone")
	assert_eq(bone_total, 2, "구간 1 의 산출이 두 번 나가면 안 된다")


func test_reconnect_restores_the_yield_mask_on_the_client_replica() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_carcass_both("Carcass", Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	var host_view_client: Player = host.container.get_node(String(client_id))
	host_view_client.inventory.add_item(STONE_KNIFE, 1)
	host.host_player.inventory.add_item(STONE_KNIFE, 1)
	var host_carcass: Carcass = _carcass_on(host, "Carcass")
	assert_true(host_carcass.apply_stage(host.host_player), "전제: 호스트가 1구간 해체")
	assert_eq(host_carcass.stages_done(), 1)
	# 클라이언트 복제본은 아직 모른다.
	assert_eq(_carcass_on(client, "Carcass").stages_done(), 0, "전제: 복제본은 아직 0구간")

	(host.butcher as NetButcher).send_world_snapshot_to(client_id)

	assert_true(await wait_until(func() -> bool:
		return _carcass_on(client, "Carcass").stages_done() == 1, 5.0),
		"재접속 스냅샷으로 이미 확정된 bit 가 복원돼야 한다")


## 배선 회귀: 스냅샷 함수가 맞아도 재접속 신호에 물려 있지 않으면 실기에서 죽는다.
## (W5 교훈: 함수를 직접 부르는 테스트는 배선 누락을 못 잡는다.)
func test_reconnect_signal_triggers_the_world_snapshot() -> void:
	var client_id: StringName = await _join_and_spawn()
	_spawn_carcass_both("Carcass", Vector2(64.0, 24.0))
	await wait_physics_frames(2)
	host.host_player.inventory.add_item(STONE_KNIFE, 1)
	assert_true(_carcass_on(host, "Carcass").apply_stage(host.host_player), "전제: 호스트가 1구간 해체")
	assert_eq(_carcass_on(client, "Carcass").stages_done(), 0, "전제: 복제본은 아직 0구간")

	# 세션이 재접속을 알리면 NetButcher 가 스스로 월드 스냅샷을 보내야 한다.
	host.session.player_reconnected.emit(client_id)

	assert_true(await wait_until(func() -> bool:
		return _carcass_on(client, "Carcass").stages_done() == 1, 5.0),
		"player_reconnected 신호만으로 사체 상태가 복원돼야 한다")

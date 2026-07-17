extends GutTest

## 원격 아바타 은신 소음 호스트 권위 반영 (W3-4 픽스2).
## ★ 버그: 클라이언트가 웅크려도 호스트 권위 감각 루프(SmellGrid._emit_remote_player_noise)
##   는 원격 이동을 고정 120px 소음으로만 봤다 — 은신 시스템이 멀티플레이에서 무력화.
## 고침: 클라이언트가 이동 의도에 자세(stance)를 실어 보내고, 호스트는 실측 속도로
## 교차검증(주장 자세의 허용 속도를 넘으면 강등)한 뒤, 검증된 자세의 NoiseProfile 로
## 발신한다. 수풀 여부는 클라이언트 주장이 아니라 호스트 트리의 아바타 위치로 정한다.
## 실제 ENet 루프백 브랜치 2개(호스트/클라이언트)로 검증한다 (tests/net 2인 하네스 관례).

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")
const StealthZoneScript = preload("res://scripts/world/stealth_zone.gd")
const CROUCH_PROFILE: NoiseProfile = preload("res://data/senses/noise_sneak.tres")
const WALK_PROFILE: NoiseProfile = preload("res://data/senses/noise_walk.tres")
const RUN_PROFILE: NoiseProfile = preload("res://data/senses/noise_run.tres")
const BUSH_RUN_PROFILE: NoiseProfile = preload("res://data/senses/noise_bush_run.tres")
const NetTestPortsScript = preload("res://tests/net/net_test_ports.gd")

var port: int
var host: Dictionary
var client: Dictionary
var _event_bus: Node = null


func before_each() -> void:
	port = NetTestPortsScript.pick_available_port(3)
	_event_bus = get_node("/root/EventBus")
	host = _make_side("HostSide")
	client = _make_side("ClientSide")
	Input.action_release(&"crouch")
	Input.action_release(&"run")


func after_each() -> void:
	client.session.leave_session()
	host.session.leave_session()
	get_tree().set_multiplayer(null, host.root.get_path())
	get_tree().set_multiplayer(null, client.root.get_path())
	Input.action_release(&"crouch")
	Input.action_release(&"run")


## 한쪽 '기계': 세션 + 호스트 아바타 + 스폰 컨테이너 + NetMovement + SmellGrid.
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

	var net: NetMovement = NetMovement.new()
	net.name = "NetMovement"
	net.session_path = ^"../NetSession"
	net.host_player_path = ^"../Player"
	net.players_container_path = ^"../Players"
	net.avatar_scene = PlayerScene
	net.config = session.config
	root.add_child(net)

	var grid_config: SmellGridConfig = SmellGridConfigScript.new()
	grid_config.cell_size = 200.0
	grid_config.tick_interval = 0.25
	var grid: SmellGrid = SmellGridScript.new()
	grid.name = "SmellGrid"
	grid.config = grid_config
	grid.area_origin = Vector2(-4000.0, -4000.0)
	grid.area_size = Vector2(8000.0, 8000.0)
	root.add_child(grid)
	# 이 테스트는 실제 물리 프레임을 여러 틱 흘려보낸다 — 자동 _process() 가 함께 돌면
	# 수동으로 건 tick 과 이중으로 겹쳐 결정성이 깨진다. 오직 수동 호출로만 진행시킨다.
	grid.set_process(false)

	return {root = root, session = session, host_player = host_player,
		container = container, net = net, grid = grid}


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


## 호스트 브랜치·클라이언트 브랜치가 한 트리에 공존하는 이 하네스에서는
## wait_physics_frames(1) 한 번에 물리 틱이 실측 2틱만큼 흐른다(교차 브랜치 폴링 특성 —
## 실측으로 확인됨). 목표 속도(px/s)를 그대로 주고 이 상수로 틱당 이동량을 역산한다.
const REAL_TICKS_PER_AWAIT: int = 2
const TICK_DELTA: float = 1.0 / 60.0

## client_side_avatar 를 목표 속도(px/s)로 실제로 이동시키며 물리 프레임을 흘려보낸다.
## 순간이동이 아니라 조금씩 옮겨야 elapsed 기반 실측 속도 계산이 의미를 갖는다.
func _move_at(avatar: Player, target_speed_px_per_second: float, awaits: int) -> void:
	var px_per_await: float = target_speed_px_per_second * REAL_TICKS_PER_AWAIT * TICK_DELTA
	for i: int in range(awaits):
		avatar.global_position.x += px_per_await
		await wait_physics_frames(1)


func test_remote_crouching_avatar_emits_crouch_radius_not_fixed_120px() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_side_avatar: Player = client.container.get_node(String(client_id))
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	var grid: SmellGrid = host.grid

	# 기준선을 잡아둔다 (첫 호출은 이동량 비교 대상이 없어 발신하지 않는다).
	grid._process(grid.config.tick_interval)

	Input.action_press(&"crouch")
	# 웅크리기 속도(70px/s) 이내로 정직하게 이동한다.
	await _move_at(client_side_avatar, 50.0, 60)

	assert_true(await wait_until(func() -> bool:
		return host_side_avatar.last_validated_stance == Player.Stance.CROUCH, 3.0),
		"실측 속도가 웅크리기 이내이면 호스트는 웅크림 주장을 그대로 받아들여야 한다")

	watch_signals(_event_bus)
	grid._process(grid.config.tick_interval)

	assert_signal_emitted(_event_bus, "noise_emitted",
		"원격 아바타의 실제 이동은 소리를 내야 한다")
	if get_signal_emit_count(_event_bus, "noise_emitted") == 0:
		return
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[1], CROUCH_PROFILE.radius,
		"웅크린 원격 아바타는 웅크리기 반경으로 발신해야 한다 (고정 120px 이 아니라)")
	assert_ne(params[1], 120.0, "예전 고정값(120px)이 아니어야 한다")


func test_remote_avatar_claiming_crouch_while_running_is_downgraded_to_run() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_side_avatar: Player = client.container.get_node(String(client_id))
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	var grid: SmellGrid = host.grid
	grid._process(grid.config.tick_interval)

	# 위조: 웅크림을 주장하지만(Input) 실제로는 달리기 속도(240px/s)로 이동시킨다.
	Input.action_press(&"crouch")
	await _move_at(client_side_avatar, 240.0, 60)

	assert_true(await wait_until(func() -> bool:
		return host_side_avatar.last_validated_stance == Player.Stance.RUN, 3.0),
		"실측 속도가 달리기에 해당하면 웅크림 주장을 신뢰하지 말고 달리기로 강등해야 한다")

	watch_signals(_event_bus)
	grid._process(grid.config.tick_interval)

	assert_signal_emitted(_event_bus, "noise_emitted")
	if get_signal_emit_count(_event_bus, "noise_emitted") == 0:
		return
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[1], RUN_PROFILE.radius,
		"위조된 웅크림 주장은 실측 속도에 맞는 달리기 반경으로 발신해야 한다")


func test_remote_avatar_walking_uses_walk_radius() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_side_avatar: Player = client.container.get_node(String(client_id))
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	var grid: SmellGrid = host.grid
	grid._process(grid.config.tick_interval)

	# 크라우치도 런도 없이 정직하게 걷기 속도(150px/s 이내)로 이동한다.
	await _move_at(client_side_avatar, 130.0, 60)

	assert_true(await wait_until(func() -> bool:
		return host_side_avatar.last_validated_stance == Player.Stance.WALK, 3.0),
		"정직한 걷기는 걷기 자세로 확정되어야 한다")

	watch_signals(_event_bus)
	grid._process(grid.config.tick_interval)

	assert_signal_emitted(_event_bus, "noise_emitted")
	if get_signal_emit_count(_event_bus, "noise_emitted") == 0:
		return
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[1], WALK_PROFILE.radius, "정직한 걷기는 걷기 반경으로 발신해야 한다")


## 수풀 여부는 클라이언트 주장이 아니라 호스트 트리의 아바타 위치로 판정한다 —
## StealthZone 은 호스트의 실제 아바타(host_side_avatar)와 겹칠 때만 in_bush 를 켠다.
func test_remote_avatar_in_bush_uses_host_determined_bush_run_profile() -> void:
	var client_id: StringName = await _join_and_spawn()
	var client_side_avatar: Player = client.container.get_node(String(client_id))
	var host_side_avatar: Player = host.container.get_node(String(client_id))
	var grid: SmellGrid = host.grid
	grid._process(grid.config.tick_interval)

	var bush: StealthZone = StealthZoneScript.new()
	bush.collision_layer = 0
	bush.collision_mask = 2
	bush.position = host_side_avatar.global_position
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(3000.0, 3000.0)
	shape.shape = rect
	bush.add_child(shape)
	host.root.add_child(bush)
	await wait_physics_frames(2)
	assert_true(host_side_avatar.in_bush, "전제: 호스트가 본 원격 아바타가 수풀 안에 있어야 한다")

	# 수풀 안에서 달린다 (호스트가 직접 판정 — 클라이언트는 in_bush 를 보내지 않는다).
	await _move_at(client_side_avatar, 240.0, 60)

	assert_true(await wait_until(func() -> bool:
		return host_side_avatar.last_validated_stance == Player.Stance.RUN, 3.0),
		"전제: 달리기로 확정되어야 한다")

	watch_signals(_event_bus)
	grid._process(grid.config.tick_interval)

	assert_signal_emitted(_event_bus, "noise_emitted")
	if get_signal_emit_count(_event_bus, "noise_emitted") == 0:
		return
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[1], BUSH_RUN_PROFILE.radius,
		"수풀 안에서 달리는 원격 아바타는 수풀 통과 반경으로 발신해야 한다")

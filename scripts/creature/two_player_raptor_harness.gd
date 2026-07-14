extends SceneTree

## 헤드리스 2인 랩터 권위 검증.
## 실행: /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s scripts/creature/two_player_raptor_harness.gd

const MainScene: PackedScene = preload("res://scenes/main.tscn")
var _frames: int = 0

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame

	var host_root: Node = _make_machine("HostMachine")
	var client_root: Node = _make_machine("ClientMachine")
	var host_main: Node2D = host_root.get_node("Main")
	var client_main: Node2D = client_root.get_node("Main")
	var host_session: SessionService = host_main.get_node("NetSession")
	var client_session: SessionService = client_main.get_node("NetSession")
	var host_net: NetMovement = host_main.get_node("NetMovement")

	var error: Error = host_session.host_session()
	if error != OK:
		return _fail("host_session 실패: %d" % error)
	error = client_session.join_session("127.0.0.1:%d" % host_net.config.port)
	if error != OK:
		return _fail("join_session 실패: %d" % error)
	if not await _wait_until(func() -> bool: return host_session.get_players().size() == 2, 10.0):
		return _fail("호스트가 클라이언트 참가를 관측하지 못했다")

	var client_id: StringName = client_session.get_local_player_id()
	var avatar_path: NodePath = NodePath("Players/%s" % client_id)
	if not await _wait_until(func() -> bool:
			return host_main.has_node(avatar_path) and client_main.has_node(avatar_path), 10.0):
		return _fail("원격 아바타가 양쪽에 스폰되지 않았다")

	var host_raptor: Raptor = host_main.get_node("Raptor")
	var client_raptor: Raptor = client_main.get_node("Raptor")
	if _raptor_count(host_main) != 1 or _raptor_count(client_main) != 1:
		return _fail("각 피어는 랩터를 정확히 한 마리만 가져야 한다")
	_make_noise_only_raptor(host_raptor)
	_make_noise_only_raptor(client_raptor)

	var host_view_of_client: Player = host_main.get_node(avatar_path)
	var client_avatar: Player = client_main.get_node(avatar_path)
	var host_grid: SmellGrid = host_main.get_node("SmellGrid")
	host_raptor.global_position = Vector2.ZERO
	client_raptor.global_position = Vector2.ZERO
	host_view_of_client.global_position = Vector2(70.0, 0.0)
	client_avatar.global_position = Vector2(70.0, 0.0)
	host_grid._process(host_grid.config.tick_interval)
	await _wait_frames(20)

	host_view_of_client.global_position = Vector2(50.0, 0.0)
	client_avatar.global_position = Vector2(50.0, 0.0)
	host_grid._process(host_grid.config.tick_interval)
	if not await _wait_until(func() -> bool: return host_raptor.state == Raptor.State.INVESTIGATE, 5.0):
		return _fail("호스트 랩터가 원격 플레이어 소리를 조사하지 않았다: %s" % host_raptor.get_state_name())
	if not await _wait_until(func() -> bool: return client_raptor.state == host_raptor.state, 5.0):
		return _fail("클라이언트 랩터 상태가 호스트와 다르다: host=%s client=%s" % [
			host_raptor.get_state_name(), client_raptor.get_state_name()])
	if not await _wait_until(func() -> bool:
			return client_raptor.global_position.distance_to(host_raptor.global_position) <= 24.0, 5.0):
		return _fail("클라이언트 랩터 위치가 호스트 스냅샷과 수렴하지 않았다")

	_log("=== 2인 랩터 하네스 성공: 단일 랩터, 호스트 AI, 원격 이동 소리 반응, 상태 복제 ===")
	quit(0)

func _make_machine(machine_name: String) -> Node:
	var root: Node = Node.new()
	root.name = machine_name
	get_root().add_child(root)
	set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var main: Node2D = MainScene.instantiate()
	main.name = "Main"
	root.add_child(main)
	return root

func _make_noise_only_raptor(raptor: Raptor) -> void:
	var data: CreatureData = raptor.data.duplicate() as CreatureData
	data.sight_radius = 20.0
	data.lose_sight_radius = 40.0
	data.occlusion_attenuation = 1.0
	raptor.data = data
	raptor.move_target = raptor.global_position

func _raptor_count(main: Node) -> int:
	var count: int = 0
	for child: Node in main.get_children():
		if child is Raptor:
			count += 1
	return count

func _wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	for frame_index: int in range(max_frames):
		if condition.call():
			return true
		await physics_frame
		_frames += 1
	return condition.call()

func _wait_frames(count: int) -> void:
	for frame_index: int in range(count):
		await physics_frame
		_frames += 1

func _log(message: String) -> void:
	print("[t=%5.1fs] %s" % [float(_frames) / 60.0, message])

func _fail(reason: String) -> void:
	_log("=== 2인 랩터 하네스 실패: %s ===" % reason)
	quit(1)

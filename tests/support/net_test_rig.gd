class_name NetTestRig
extends RefCounted

var _tree: SceneTree
var _services: Array[LocalSessionService] = []


func _init(tree: SceneTree) -> void:
	_tree = tree


func start_host(host: LocalSessionService) -> Error:
	_prepare_dynamic_config(host)
	_track(host)
	return host.host_session()


func connect_client(client: LocalSessionService, host: LocalSessionService,
		player_id: StringName = &"") -> Error:
	_track(client)
	var invite: Variant = "127.0.0.1:%d" % host.bound_port
	if not String(player_id).is_empty():
		invite = {
			address = "127.0.0.1",
			port = host.bound_port,
			player_id = player_id,
			host_build_number = host.build_number,
		}
	return client.join_session(invite)


func pump_until(condition: Callable, timeout_seconds: float,
		report: Callable = Callable()) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	for frame_index: int in range(max_frames):
		if condition.call():
			return true
		if report.is_valid() and frame_index % 60 == 0:
			report.call()
		await _tree.physics_frame
	return condition.call()


func disconnect_all() -> void:
	for index: int in range(_services.size() - 1, -1, -1):
		_services[index].leave_session()
	_services.clear()
	LocalSessionService.clear_for_test()


func assert_no_leaked_peers() -> bool:
	for service: LocalSessionService in _services:
		if service.multiplayer.multiplayer_peer != null \
				and not (service.multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
			push_error("NetTestRig leaked an active peer: %s" % service.get_path())
			return false
	return true


func _prepare_dynamic_config(host: LocalSessionService) -> void:
	host.config = host.config.duplicate()
	host.config.port = 0


func _track(service: LocalSessionService) -> void:
	if not _services.has(service):
		_services.append(service)

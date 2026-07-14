extends GutTest

## LocalSessionService — SessionService 계약 검증.
## 한 프로세스에서 SceneTree.set_multiplayer 브랜치 2개로 실제 ENet 루프백을 쓴다.
## 게임 코드가 보는 것은 SessionService 인터페이스뿐이다.

const PORT: int = 8911

var host_root: Node
var client_root: Node
var host_service: SessionService
var client_service: SessionService


func before_each() -> void:
	host_root = _make_branch("HostRoot")
	client_root = _make_branch("ClientRoot")
	host_service = _make_service(host_root)
	client_service = _make_service(client_root)


func after_each() -> void:
	client_service.leave_session()
	host_service.leave_session()
	# 브랜치 API 등록 해제 — 다른 테스트 오염 방지.
	get_tree().set_multiplayer(null, host_root.get_path())
	get_tree().set_multiplayer(null, client_root.get_path())


func _make_branch(branch_name: String) -> Node:
	var root: Node = add_child_autofree(Node.new())
	root.name = branch_name
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())
	return root


func _make_service(parent: Node) -> SessionService:
	var service: LocalSessionService = LocalSessionService.new()
	service.config = NetConfig.new()
	service.config.port = PORT
	parent.add_child(service)
	return service


func _join() -> void:
	assert_eq(host_service.host_session(), OK)
	assert_eq(client_service.join_session("127.0.0.1:%d" % PORT), OK)
	await wait_for_signal(host_service.player_joined, 5.0, "호스트가 참가를 관측해야 한다")


func test_host_session_registers_local_player_one() -> void:
	assert_eq(host_service.host_session(), OK)
	assert_eq(host_service.get_local_player_id(), &"1")
	assert_eq(host_service.get_players(), [&"1"] as Array[StringName])


func test_offline_service_reports_single_local_host() -> void:
	# 설계서 9.3: 싱글플레이도 '로컬 호스트 한 명인 동일 흐름'.
	assert_eq(host_service.get_local_player_id(), &"1")
	assert_eq(host_service.get_players(), [&"1"] as Array[StringName])


func test_join_is_observed_on_both_sides() -> void:
	await _join()
	var client_id: StringName = client_service.get_local_player_id()
	assert_ne(client_id, &"1")
	assert_has(host_service.get_players(), client_id)
	assert_has(host_service.get_players(), &"1")
	assert_has(client_service.get_players(), &"1")
	assert_has(client_service.get_players(), client_id)
	assert_eq(host_service.get_players().size(), 2)


func test_peer_and_player_id_mapping_round_trips() -> void:
	await _join()
	var client_id: StringName = client_service.get_local_player_id()
	var peer: int = host_service.get_peer_for_player(client_id)
	assert_gt(peer, 1)
	assert_eq(host_service.get_player_id_for_peer(peer), client_id)
	assert_eq(host_service.get_peer_for_player(&"1"), 1)


func test_invalid_invite_is_rejected() -> void:
	assert_eq(client_service.join_session(12345), ERR_INVALID_PARAMETER)
	assert_eq(client_service.join_session("주소도아니고포트도없음"), ERR_INVALID_PARAMETER)


func test_client_leave_emits_player_left_on_host() -> void:
	await _join()
	var client_id: StringName = client_service.get_local_player_id()
	watch_signals(host_service)
	client_service.leave_session()
	await wait_for_signal(host_service.player_left, 5.0, "호스트가 이탈을 관측해야 한다")
	assert_signal_emitted_with_parameters(host_service, "player_left", [client_id])
	assert_eq(host_service.get_players(), [&"1"] as Array[StringName])


func test_leave_emits_session_ended_locally() -> void:
	await _join()
	watch_signals(client_service)
	client_service.leave_session()
	assert_signal_emitted(client_service, "session_ended")
	assert_eq(client_service.get_players().size(), 1)

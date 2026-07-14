extends GutTest

## RpcGuard — RPC 보안 골격 (설계서 7.4).
## 허용 발신자 / 호출 빈도 상한 / 최대 페이로드 / 미등록 RPC 기본 거부.

const CLIENT_PEER: int = 200
const OTHER_PEER: int = 300

var guard: RpcGuard


func before_each() -> void:
	guard = RpcGuard.new()
	guard.register_rule(&"submit_move_intent", false, 3, 64)
	guard.register_rule(&"spawn_avatar", true, 5, 256)
	guard.add_peer(RpcGuard.HOST_PEER_ID)
	guard.add_peer(CLIENT_PEER)


func test_valid_call_from_known_peer_passes() -> void:
	assert_true(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 0.0))
	assert_eq(guard.get_violation_count(CLIENT_PEER), 0)


func test_unregistered_rpc_is_rejected_by_default() -> void:
	assert_false(guard.check(&"no_such_rpc", CLIENT_PEER, 16, 0.0))
	assert_eq(guard.get_violation_count(CLIENT_PEER), 1)


func test_unknown_sender_is_rejected() -> void:
	assert_false(guard.check(&"submit_move_intent", OTHER_PEER, 16, 0.0))
	assert_eq(guard.get_violation_count(OTHER_PEER), 1)


func test_removed_peer_is_rejected() -> void:
	guard.remove_peer(CLIENT_PEER)
	assert_false(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 0.0))


func test_host_only_rpc_from_client_is_rejected_and_logged() -> void:
	watch_signals(guard)
	assert_false(guard.check(&"spawn_avatar", CLIENT_PEER, 16, 0.0))
	assert_eq(guard.get_violation_count(CLIENT_PEER), 1)
	assert_signal_emitted_with_parameters(
		guard, "violation_recorded", [CLIENT_PEER, &"spawn_avatar", &"host_only"])


func test_host_only_rpc_from_host_passes() -> void:
	assert_true(guard.check(&"spawn_avatar", RpcGuard.HOST_PEER_ID, 16, 0.0))


func test_oversized_payload_is_rejected() -> void:
	assert_false(guard.check(&"submit_move_intent", CLIENT_PEER, 65, 0.0))
	assert_eq(guard.get_violation_count(CLIENT_PEER), 1)


func test_rate_limit_blocks_fourth_call_in_same_second() -> void:
	assert_true(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 10.0))
	assert_true(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 10.1))
	assert_true(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 10.2))
	assert_false(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 10.3))
	assert_eq(guard.get_violation_count(CLIENT_PEER), 1)


func test_rate_limit_resets_after_window() -> void:
	for i: int in range(3):
		guard.check(&"submit_move_intent", CLIENT_PEER, 16, 10.0)
	assert_false(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 10.5))
	assert_true(guard.check(&"submit_move_intent", CLIENT_PEER, 16, 11.1))


func test_rate_limit_is_per_sender() -> void:
	for i: int in range(3):
		guard.check(&"submit_move_intent", CLIENT_PEER, 16, 10.0)
	assert_true(guard.check(&"submit_move_intent", RpcGuard.HOST_PEER_ID, 16, 10.0))

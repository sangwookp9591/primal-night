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


## 세션 시그널만 흉내 내는 최소 스텁 — watch_session 의 피어 수명주기 검증용.
class SessionStub extends SessionService:
	var peers: Dictionary = {}
	func host_session() -> Error: return OK
	func join_session(_invite: Variant) -> Error: return OK
	func leave_session() -> void: pass
	func get_local_player_id() -> StringName: return &"host"
	func get_players() -> Array[StringName]: return []
	func get_player_id_for_peer(_peer_id: int) -> StringName: return &""
	func get_peer_for_player(player_id: StringName) -> int: return int(peers.get(player_id, 0))
	func has_reconnect_slot(_player_id: StringName) -> bool: return false
	func get_reconnect_slot_remaining(_player_id: StringName) -> float: return 0.0
	func tick_reconnect_slots(_delta_seconds: float) -> void: pass
	func get_last_connection_failure() -> Dictionary: return {}


## ★ 허용 발신자 명부는 RpcGuard 가 세션에서 직접 유지한다 — 노드마다 구독을
## 복제하다 player_reconnected 를 빠뜨리면 재접속 피어의 모든 의도 RPC 가
## unknown_sender 로 죽는다 (W2-T5 에서 실제로 발생한 버그 계급).
func test_watch_session_tracks_join_reconnect_and_leave() -> void:
	var session: SessionStub = autofree(SessionStub.new())
	guard.watch_session(session)

	assert_false(guard.check(&"submit_move_intent", 400, 16, 0.0), "참가 전 피어는 거부된다")

	session.peers[&"friend"] = 400
	session.player_joined.emit(&"friend")
	assert_true(guard.check(&"submit_move_intent", 400, 16, 1.0), "참가한 피어는 허용된다")

	session.player_left.emit(&"friend")
	assert_false(guard.check(&"submit_move_intent", 400, 16, 2.0), "이탈한 피어는 거부된다")

	# 재접속은 새 peer id 로 돌아온다 — 재등록되어야 한다.
	session.peers[&"friend"] = 500
	session.player_reconnected.emit(&"friend")
	assert_true(guard.check(&"submit_move_intent", 500, 16, 3.0),
		"재접속 피어(새 peer id)가 재등록되어야 한다")


## 상대 경로 페이로드의 명시적 스키마 (설계서 7.4) — 분산 인라인 검사 대신 공용 규칙.
func test_is_safe_relative_path_schema() -> void:
	assert_true(RpcGuard.is_safe_relative_path("Items/Stone", 128), "정상 상대 경로는 허용")
	assert_false(RpcGuard.is_safe_relative_path("", 128), "빈 경로 거부")
	assert_false(RpcGuard.is_safe_relative_path("/root/EventBus", 128), "절대 경로 거부")
	assert_false(RpcGuard.is_safe_relative_path("../../Player", 128), "상위 탈출 거부")
	assert_false(RpcGuard.is_safe_relative_path("a".repeat(129), 128), "길이 상한 초과 거부")

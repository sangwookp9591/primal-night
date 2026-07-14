class_name RpcGuard
extends RefCounted

## RPC 보안 골격 (설계서 7.4 / 성능 문서 14).
## RPC 마다 허용 발신자(호스트 전용), 초당 호출 상한, 최대 페이로드를 검사한다.
## 세션 구성원이 아닌 발신자는 폐기하고, 위반은 연결별로 계수·로그한다.
## 로그에 IP·토큰을 남기지 않는다 — peer id 만 기록한다.
## ponytail: 반복 위반 시 연결 종료는 다음 태스크 — violation_recorded 를 구독해 얹는다.

signal violation_recorded(sender_id: int, rpc_name: StringName, reason: StringName)

const HOST_PEER_ID: int = 1
const RATE_WINDOW_SECONDS: float = 1.0

var _rules: Dictionary = {}
var _known_peers: Dictionary = {}
var _violation_counts: Dictionary = {}


## 세션의 참가·재접속·이탈에 맞춰 허용 발신자 명부를 자동 유지한다.
## 재접속 피어는 새 peer id 를 받으므로 재등록이 필수다 — 노드마다 구독을 복제하다
## reconnected 를 빠뜨리면 재접속 피어의 모든 의도 RPC 가 unknown_sender 로 죽는다
## (tests/net/test_net_resync.gd 가 잡았던 버그 계급을 여기서 원천 차단한다).
func watch_session(session: SessionService) -> void:
	session.player_joined.connect(_on_watched_player_active.bind(session))
	session.player_reconnected.connect(_on_watched_player_active.bind(session))
	session.player_left.connect(_on_watched_player_left.bind(session))


## 상대 경로 페이로드의 명시적 스키마 (설계서 7.4): 비어 있지 않고, 길이 상한 안이며,
## 절대 경로(/)나 상위 탈출(..)로 월드 밖을 가리키지 않는다.
static func is_safe_relative_path(path: String, max_length: int) -> bool:
	return not path.is_empty() and path.length() <= max_length \
		and not path.begins_with("/") and not path.contains("..")


func register_rule(rpc_name: StringName, host_only: bool, max_calls_per_second: int, max_payload_bytes: int) -> void:
	_rules[rpc_name] = {
		host_only = host_only,
		max_calls_per_second = max_calls_per_second,
		max_payload_bytes = max_payload_bytes,
		windows = {},  # sender_id -> [창 시작 시각, 창 내 호출 수]
	}


func add_peer(peer_id: int) -> void:
	_known_peers[peer_id] = true


func remove_peer(peer_id: int) -> void:
	_known_peers.erase(peer_id)


## 수신한 원격 호출을 허용할지 판정한다. 거부 시 위반을 기록한다.
## now_seconds 는 호출자가 주입한다 (테스트 결정성).
func check(rpc_name: StringName, sender_id: int, payload_bytes: int, now_seconds: float) -> bool:
	var rule: Dictionary = _rules.get(rpc_name, {})
	if rule.is_empty():
		return _reject(sender_id, rpc_name, &"unregistered_rpc")
	if not _known_peers.has(sender_id):
		return _reject(sender_id, rpc_name, &"unknown_sender")
	if bool(rule.host_only) and sender_id != HOST_PEER_ID:
		return _reject(sender_id, rpc_name, &"host_only")
	if payload_bytes > int(rule.max_payload_bytes):
		return _reject(sender_id, rpc_name, &"payload_too_large")

	var windows: Dictionary = rule.windows
	var window: Array = windows.get(sender_id, [])
	if window.is_empty():
		window = [now_seconds, 0]
		windows[sender_id] = window
	if now_seconds - float(window[0]) >= RATE_WINDOW_SECONDS:
		window[0] = now_seconds
		window[1] = 0
	window[1] = int(window[1]) + 1
	if int(window[1]) > int(rule.max_calls_per_second):
		return _reject(sender_id, rpc_name, &"rate_limited")
	return true


func get_violation_count(sender_id: int) -> int:
	return _violation_counts.get(sender_id, 0)


func _on_watched_player_active(player_id: StringName, session: SessionService) -> void:
	add_peer(session.get_peer_for_player(player_id))


func _on_watched_player_left(player_id: StringName, session: SessionService) -> void:
	remove_peer(session.get_peer_for_player(player_id))


func _reject(sender_id: int, rpc_name: StringName, reason: StringName) -> bool:
	_violation_counts[sender_id] = int(_violation_counts.get(sender_id, 0)) + 1
	push_warning("RpcGuard: 거부 rpc=%s sender=%d reason=%s count=%d" % [
		rpc_name, sender_id, reason, int(_violation_counts[sender_id])])
	violation_recorded.emit(sender_id, rpc_name, reason)
	return false

class_name LocalSessionService
extends SessionService

## ENet 기반 로컬 세션 (개발·로컬 2인용). ENet 은 이 파일 밖으로 새지 않는다.
## 출시 시 SteamSessionService 가 같은 SessionService 인터페이스로 교체된다.
##
## 상태를 따로 들고 있지 않다 — 참가자 목록과 peer↔PlayerId 변환을 전부
## MultiplayerAPI 에서 유도해 접속 신호 순서 경쟁을 원천 차단한다.
## (Steam 구현은 SteamID↔peer 매핑 상태가 필요하지만 인터페이스는 동일하다.)

const DEFAULT_CONFIG: NetConfig = preload("res://resources/net/net_config.tres")
const RECONNECT_SLOT_SECONDS: float = 120.0
const DYNAMIC_PORT_BASE: int = 20000
const DYNAMIC_PORT_SPAN: int = 32768
const DYNAMIC_PORT_ATTEMPTS: int = 256

static var _pending_player_ids_by_port: Dictionary = {}
static var _dynamic_port_cursor: int = 0

@export var config: NetConfig = DEFAULT_CONFIG
@export var build_number: String = "dev"

var _peer_to_player: Dictionary = {}
var _player_to_peer: Dictionary = {}
var _reconnect_slots: Dictionary = {}
var _last_connection_failure: Dictionary = {}
var bound_port: int = 0
var _pending_player_id_port: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_session() -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if config.port == 0:
		var result: Dictionary = _create_server_on_dynamic_port(peer)
		error = result.error
		bound_port = result.port
	else:
		error = peer.create_server(config.port, config.max_clients)
		bound_port = config.port if error == OK else 0
	if error != OK:
		_record_connection_failure(&"host_create_failed", error, "", build_number)
		return error
	multiplayer.multiplayer_peer = peer
	_set_peer_player_id(multiplayer.get_unique_id(), _player_id_from_peer(multiplayer.get_unique_id()))
	return OK


func join_session(invite: Variant) -> Error:
	var parsed: Dictionary = _parse_invite(invite)
	if parsed.is_empty():
		_record_connection_failure(&"invalid_invite", ERR_INVALID_PARAMETER, "", build_number)
		return ERR_INVALID_PARAMETER
	if String(parsed["host_build_number"]) != build_number:
		_record_connection_failure(&"version_mismatch", ERR_INVALID_DATA,
			String(parsed["host_build_number"]), build_number)
		return ERR_INVALID_DATA

	var requested_player_id: StringName = parsed["player_id"]
	if not String(requested_player_id).is_empty():
		_pending_player_ids_by_port[int(parsed["port"])] = requested_player_id
		_pending_player_id_port = int(parsed["port"])
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(String(parsed["address"]), int(parsed["port"]))
	if error != OK:
		_clear_pending_player_id()
		_record_connection_failure(&"client_create_failed", error, String(parsed["host_build_number"]), build_number)
		return error
	multiplayer.multiplayer_peer = peer
	if not String(requested_player_id).is_empty():
		_set_peer_player_id(multiplayer.get_unique_id(), requested_player_id)
	_last_connection_failure = {}
	return OK


func leave_session() -> void:
	_clear_pending_player_id()
	if _has_session():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		session_ended.emit()
	if bound_port != 0:
		_pending_player_ids_by_port.erase(bound_port)
	bound_port = 0
	_peer_to_player.clear()
	_player_to_peer.clear()


func get_local_player_id() -> StringName:
	return _peer_to_player.get(multiplayer.get_unique_id(), _player_id_from_peer(multiplayer.get_unique_id()))


func get_players() -> Array[StringName]:
	var players: Array[StringName] = [get_local_player_id()]
	for peer_id: int in multiplayer.get_peers():
		players.append(get_player_id_for_peer(peer_id))
	players.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return players


func get_player_id_for_peer(peer_id: int) -> StringName:
	return _peer_to_player.get(peer_id, _player_id_from_peer(peer_id))


func get_peer_for_player(player_id: StringName) -> int:
	if player_id == get_local_player_id():
		return multiplayer.get_unique_id()
	return int(_player_to_peer.get(player_id, 0))


func has_reconnect_slot(player_id: StringName) -> bool:
	return _reconnect_slots.has(player_id)


func get_reconnect_slot_remaining(player_id: StringName) -> float:
	return float(_reconnect_slots.get(player_id, 0.0))


func tick_reconnect_slots(delta_seconds: float) -> void:
	for player_id: StringName in _reconnect_slots.keys():
		var remaining: float = float(_reconnect_slots[player_id]) - delta_seconds
		if remaining <= 0.0:
			_reconnect_slots.erase(player_id)
		else:
			_reconnect_slots[player_id] = remaining


func get_last_connection_failure() -> Dictionary:
	return _last_connection_failure.duplicate()

func record_async_connection_failure() -> void:
	_record_connection_failure(&"connection_failed", ERR_CANT_CONNECT, "", build_number)


func _has_session() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


func _player_id_from_peer(peer_id: int) -> StringName:
	return StringName(str(peer_id))


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		_set_peer_player_id(peer_id, _player_id_from_peer(peer_id))
		player_joined.emit(_player_id_from_peer(peer_id))
		return
	var player_id: StringName = _pending_player_ids_by_port.get(bound_port, _player_id_from_peer(peer_id))
	_pending_player_ids_by_port.erase(bound_port)
	_set_peer_player_id(peer_id, player_id)
	if _reconnect_slots.has(player_id):
		_reconnect_slots.erase(player_id)
		player_reconnected.emit(player_id)
	else:
		player_joined.emit(player_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var player_id: StringName = get_player_id_for_peer(peer_id)
	_reconnect_slots[player_id] = RECONNECT_SLOT_SECONDS
	player_left.emit(player_id)
	_peer_to_player.erase(peer_id)
	_player_to_peer.erase(player_id)


func _on_server_disconnected() -> void:
	# 호스트 이탈: 세션 종료 (설계서 7.3). 호스트 이전은 출시 범위 밖이다.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_pending_player_id()
	session_ended.emit()


func _set_peer_player_id(peer_id: int, player_id: StringName) -> void:
	_peer_to_player[peer_id] = player_id
	_player_to_peer[player_id] = peer_id


func _parse_invite(invite: Variant) -> Dictionary:
	if typeof(invite) == TYPE_STRING:
		var parts: PackedStringArray = (invite as String).split(":")
		if parts.size() != 2 or parts[0].is_empty() or not parts[1].is_valid_int():
			return {}
		return {
			address = parts[0],
			port = int(parts[1]),
			player_id = &"",
			host_build_number = build_number,
		}
	if typeof(invite) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = invite
	if not data.has("address") or not data.has("port") or not data.has("player_id"):
		return {}
	if String(data["address"]).is_empty() or not (data["port"] is int):
		return {}
	return {
		address = String(data["address"]),
		port = int(data["port"]),
		player_id = data["player_id"] as StringName,
		host_build_number = String(data.get("host_build_number", build_number)),
	}


func _record_connection_failure(reason: StringName, error: Error, host_build: String, local_build: String) -> void:
	_last_connection_failure = {
		reason = reason,
		error = error,
		host_build_number = host_build,
		local_build_number = local_build,
		can_return_single_player = true,
	}


func _create_server_on_dynamic_port(peer: ENetMultiplayerPeer) -> Dictionary:
	var start: int = (OS.get_process_id() + _dynamic_port_cursor) % DYNAMIC_PORT_SPAN
	for offset: int in range(DYNAMIC_PORT_ATTEMPTS):
		var candidate: int = DYNAMIC_PORT_BASE + ((start + offset) % DYNAMIC_PORT_SPAN)
		var probe: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		if probe.create_server(candidate, 1) != OK:
			continue
		probe.close()
		var error: Error = peer.create_server(candidate, config.max_clients)
		if error == OK:
			_dynamic_port_cursor = (_dynamic_port_cursor + offset + 1) % DYNAMIC_PORT_SPAN
			return {error = OK, port = candidate}
	return {error = ERR_CANT_CREATE, port = 0}


func _clear_pending_player_id() -> void:
	if _pending_player_id_port != 0:
		_pending_player_ids_by_port.erase(_pending_player_id_port)
		_pending_player_id_port = 0


static func clear_for_test() -> void:
	_pending_player_ids_by_port.clear()

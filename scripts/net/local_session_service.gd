class_name LocalSessionService
extends SessionService

## ENet 기반 로컬 세션 (개발·로컬 2인용). ENet 은 이 파일 밖으로 새지 않는다.
## 출시 시 SteamSessionService 가 같은 SessionService 인터페이스로 교체된다.
##
## 상태를 따로 들고 있지 않다 — 참가자 목록과 peer↔PlayerId 변환을 전부
## MultiplayerAPI 에서 유도해 접속 신호 순서 경쟁을 원천 차단한다.
## (Steam 구현은 SteamID↔peer 매핑 상태가 필요하지만 인터페이스는 동일하다.)

const DEFAULT_CONFIG: NetConfig = preload("res://resources/net/net_config.tres")

@export var config: NetConfig = DEFAULT_CONFIG


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_session() -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(config.port, config.max_clients)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


func join_session(invite: Variant) -> Error:
	# ENet 초대장 스키마: "주소:포트" String 만 허용 (설계서 7.4: 명시적 스키마).
	if typeof(invite) != TYPE_STRING:
		return ERR_INVALID_PARAMETER
	var parts: PackedStringArray = (invite as String).split(":")
	if parts.size() != 2 or parts[0].is_empty() or not parts[1].is_valid_int():
		return ERR_INVALID_PARAMETER
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(parts[0], int(parts[1]))
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


func leave_session() -> void:
	if not _has_session():
		return
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session_ended.emit()


func get_local_player_id() -> StringName:
	return _player_id_from_peer(multiplayer.get_unique_id())


func get_players() -> Array[StringName]:
	var players: Array[StringName] = [get_local_player_id()]
	for peer_id: int in multiplayer.get_peers():
		players.append(_player_id_from_peer(peer_id))
	players.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return players


func get_player_id_for_peer(peer_id: int) -> StringName:
	return _player_id_from_peer(peer_id)


func get_peer_for_player(player_id: StringName) -> int:
	return int(String(player_id))


func _has_session() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


func _player_id_from_peer(peer_id: int) -> StringName:
	return StringName(str(peer_id))


func _on_peer_connected(peer_id: int) -> void:
	player_joined.emit(_player_id_from_peer(peer_id))


func _on_peer_disconnected(peer_id: int) -> void:
	player_left.emit(_player_id_from_peer(peer_id))


func _on_server_disconnected() -> void:
	# 호스트 이탈: 세션 종료 (설계서 7.3). 재접속 슬롯은 이후 태스크.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session_ended.emit()

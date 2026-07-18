class_name NetEquipment
extends Node

## 장비 복제 경계. 클라이언트는 자신의 PlayerId와 장착/해제 의도만 보내며,
## 호스트가 EquipmentComponent의 검증·트랜잭션 경로로 확정한 뒤 작은 스냅샷을
## 모든 피어에 복제한다. 텍스처 경로나 클라이언트가 만든 스냅샷은 받지 않는다.

const REQUEST_MAX_PER_SECOND: int = 12
const SNAPSHOT_MAX_PER_SECOND: int = 64
const REQUEST_PAYLOAD_BYTES: int = 96
const SNAPSHOT_PAYLOAD_BYTES: int = 256
const PLAYER_ID_MAX_LENGTH: int = 32
const ITEM_ID_MAX_LENGTH: int = 64

const ACTION_EQUIP: int = 0
const ACTION_UNEQUIP: int = 1

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _guard: RpcGuard
var _now_seconds: float = 0.0
var _saved_snapshots: Dictionary = {}
var _rejection_count: int = 0


func _ready() -> void:
	add_to_group(&"net_equipment")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_guard = RpcGuard.new()
	_guard.register_rule(&"submit_equipment_intent", false,
		REQUEST_MAX_PER_SECOND, REQUEST_PAYLOAD_BYTES)
	_guard.register_rule(&"apply_equipment_snapshot", true,
		SNAPSHOT_MAX_PER_SECOND, SNAPSHOT_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_guard.watch_session(_session)
	_session.player_joined.connect(_on_player_joined)
	_session.player_reconnected.connect(_on_player_reconnected)
	_session.player_left.connect(_on_player_left)
	_session.session_ended.connect(_on_session_ended)


func _physics_process(delta: float) -> void:
	_now_seconds += delta


## UI/게임플레이의 단일 네트워크 진입점. 오프라인/호스트도 같은 호스트 확정
## 함수를 거치고, 클라이언트는 로컬 EquipmentComponent를 변경하지 않는다.
func request_equip(avatar: Player, item_id: StringName) -> bool:
	return _request(avatar, ACTION_EQUIP, item_id)


func request_unequip(avatar: Player, slot: StringName) -> bool:
	return _request(avatar, ACTION_UNEQUIP, slot)


func get_rejection_count() -> int:
	return _rejection_count


func get_guard_violation_count(peer_id: int) -> int:
	return _guard.get_violation_count(peer_id)


func _request(avatar: Player, action: int, value: StringName) -> bool:
	if avatar == null or avatar.controller_peer_id != multiplayer.get_unique_id():
		_reject("로컬 소유가 아닌 아바타 요청")
		return false
	var player_id := StringName(avatar.name)
	if avatar == _host_player:
		player_id = _session.get_local_player_id()
	if multiplayer.is_server():
		return _confirm_intent(player_id, action, value)
	submit_equipment_intent.rpc_id(
		RpcGuard.HOST_PEER_ID, String(player_id), action, String(value))
	return true


## claimed_player_id는 진단과 변조 테스트를 위해 명시적으로 받되, 호스트는 반드시
## remote sender에서 유도한 PlayerId와 일치하는 경우에만 처리한다.
@rpc("any_peer", "call_remote", "reliable")
func submit_equipment_intent(claimed_player_id: String, action: int, value: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var payload := claimed_player_id.length() + value.length() + 8
	if not _guard.check(&"submit_equipment_intent", sender, payload, _now_seconds):
		_rejection_count += 1
		return
	var sender_player_id: StringName = _session.get_player_id_for_peer(sender)
	if claimed_player_id.is_empty() or claimed_player_id.length() > PLAYER_ID_MAX_LENGTH \
			or String(sender_player_id) != claimed_player_id:
		_reject("타인 아바타 조작 시도 sender=%d claimed=%s" % [sender, claimed_player_id])
		return
	_confirm_intent(sender_player_id, action, StringName(value))


func _confirm_intent(player_id: StringName, action: int, value: StringName) -> bool:
	if String(value).is_empty() or String(value).length() > ITEM_ID_MAX_LENGTH:
		_reject("잘못된 장비 요청 player=%s value=%s" % [player_id, value])
		return false
	var avatar: Player = _avatar_of(player_id)
	if avatar == null:
		_reject("장비 대상 아바타 없음 player=%s" % player_id)
		return false
	var accepted: bool = false
	match action:
		ACTION_EQUIP:
			accepted = avatar.equipment.request_equip(value)
		ACTION_UNEQUIP:
			accepted = avatar.equipment.request_unequip(value)
		_:
			_reject("알 수 없는 장비 동작 player=%s action=%d" % [player_id, action])
			return false
	if not accepted:
		_reject("장비 검증 거부 player=%s action=%d value=%s" % [player_id, action, value])
		return false
	_broadcast_snapshot(player_id, avatar.equipment.get_snapshot())
	return true


## 호스트가 확정한 고정 스키마만 수신한다. apply_snapshot이 equipment_changed를
## 발생시키므로 원격 PlayerVisualRig도 로컬과 동일한 레이어 경로로 갱신된다.
@rpc("authority", "call_remote", "reliable")
func apply_equipment_snapshot(player_id: String, outfit: String, back: String,
		main_hand: String, condition_flags: int) -> void:
	var payload := player_id.length() + outfit.length() + back.length() \
		+ main_hand.length() + 16
	if not _guard.check(&"apply_equipment_snapshot",
			multiplayer.get_remote_sender_id(), payload, _now_seconds):
		return
	if player_id.is_empty() or player_id.length() > PLAYER_ID_MAX_LENGTH \
			or outfit.length() > ITEM_ID_MAX_LENGTH or back.length() > ITEM_ID_MAX_LENGTH \
			or main_hand.length() > ITEM_ID_MAX_LENGTH or condition_flags < 0:
		push_warning("NetEquipment: 장비 스냅샷 스키마 위반 — 폐기")
		return
	var avatar: Player = _avatar_of(StringName(player_id))
	if avatar == null:
		push_warning("NetEquipment: 장비 스냅샷 대상 없음 player=%s" % player_id)
		return
	if not avatar.equipment.apply_snapshot({
			outfit = StringName(outfit),
			back = StringName(back),
			main_hand = StringName(main_hand),
			condition_flags = condition_flags,
		}):
		push_warning("NetEquipment: 유효하지 않은 장비 스냅샷 player=%s" % player_id)


func _on_player_joined(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	_saved_snapshots.erase(player_id)
	var peer := _session.get_peer_for_player(player_id)
	# NetMovement가 먼저 연결되어 있으므로 이 시점에는 새 아바타가 양쪽에 reliable
	# spawn 큐에 들어가 있다. 새 피어에는 기존 전원의 상태를, 기존 피어에는 신입 상태를 보낸다.
	for existing_id: StringName in _all_player_ids():
		var avatar := _avatar_of(existing_id)
		if avatar != null:
			_send_snapshot_to(peer, existing_id, avatar.equipment.get_snapshot())
	var joined_avatar := _avatar_of(player_id)
	if joined_avatar != null:
		_broadcast_snapshot(player_id, joined_avatar.equipment.get_snapshot())


func _on_player_left(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var avatar := _avatar_of(player_id)
	if avatar != null and avatar != _host_player:
		_saved_snapshots[player_id] = avatar.equipment.get_snapshot()


func _on_player_reconnected(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var avatar := _avatar_of(player_id)
	if avatar == null:
		return
	var saved: Dictionary = _saved_snapshots.get(player_id, {})
	_saved_snapshots.erase(player_id)
	if not saved.is_empty() and not avatar.equipment.apply_snapshot(saved):
		_reject("재접속 장비 복원 실패 player=%s" % player_id)
	var peer := _session.get_peer_for_player(player_id)
	for existing_id: StringName in _all_player_ids():
		var existing := _avatar_of(existing_id)
		if existing != null:
			_send_snapshot_to(peer, existing_id, existing.equipment.get_snapshot())
	_broadcast_snapshot(player_id, avatar.equipment.get_snapshot())


func _on_session_ended() -> void:
	_saved_snapshots.clear()


func _broadcast_snapshot(player_id: StringName, snapshot: Dictionary) -> void:
	if multiplayer.get_peers().is_empty():
		return
	apply_equipment_snapshot.rpc(String(player_id), String(snapshot.outfit),
		String(snapshot.back), String(snapshot.main_hand), int(snapshot.condition_flags))


func _send_snapshot_to(peer_id: int, player_id: StringName, snapshot: Dictionary) -> void:
	if peer_id <= 0:
		return
	apply_equipment_snapshot.rpc_id(peer_id, String(player_id), String(snapshot.outfit),
		String(snapshot.back), String(snapshot.main_hand), int(snapshot.condition_flags))


func _all_player_ids() -> Array[StringName]:
	var ids: Array[StringName] = [_session.get_local_player_id()]
	for child: Node in _container.get_children():
		var id := StringName(child.name)
		if not ids.has(id):
			ids.append(id)
	return ids


func _avatar_of(player_id: StringName) -> Player:
	# 각 브랜치의 정적 Player 노드는 언제나 호스트 아바타다. 클라이언트의
	# get_local_player_id()는 자기 원격 아바타 ID이므로 여기서 쓰면 대상을 뒤바꾼다.
	if player_id == _session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID):
		return _host_player
	return _container.get_node_or_null(NodePath(String(player_id))) as Player


func _reject(reason: String) -> void:
	_rejection_count += 1
	push_warning("NetEquipment: 요청 거부 — %s" % reason)

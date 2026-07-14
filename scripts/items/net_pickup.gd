class_name NetPickup
extends Node

## 아이템 획득 호스트 권위 (설계서 7.2/7.4).
## 클라이언트는 '줍기 의도'(아이템 경로)만 보낸다 — 아이템 id·수량은 페이로드에 없어
## 클라이언트가 조작할 수 없다. 호스트가 자기 월드의 실제 WorldItem 을 조회해
## 존재·수량·거리를 검증하고 결과를 신뢰 전송으로 복제한다.
## 같은 프레임에 두 명이 같은 아이템을 요청해도 호스트가 직렬로 처리하므로
## 정확히 한 명만 획득한다 (복제 0, 소실 0) — tests/inventory/test_net_pickup.gd.

## 줍기 검증 거리 (px): 상호작용 손 반경 48 + 아이템 겹침 여유 + 10Hz 위치 스냅샷
## 지연 여유. 게임 규칙이 아니라 변조 방지 슬랙이라 프로토콜 상수다 (NetMovement 관례).
const PICKUP_MAX_DISTANCE_PX: float = 128.0
const ITEM_PATH_MAX_LENGTH: int = 128
const REQUEST_MAX_PER_SECOND: int = 10
const CONFIRM_MAX_PER_SECOND: int = 30
const CONFIRM_PAYLOAD_BYTES: int = 512

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
## 아이템 경로 해석 기준. 양쪽 기계가 같은 씬을 로드하므로 상대 경로가 일치한다.
@export var world_root_path: NodePath = ^".."

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _world_root: Node
var _guard: RpcGuard
var _event_bus: Node = null
var _now_seconds: float = 0.0


func _ready() -> void:
	add_to_group(&"net_pickup")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_world_root = get_node(world_root_path)
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	_guard = RpcGuard.new()
	_guard.register_rule(&"request_pickup", false, REQUEST_MAX_PER_SECOND, ITEM_PATH_MAX_LENGTH + 16)
	_guard.register_rule(&"confirm_pickup", true, CONFIRM_MAX_PER_SECOND, CONFIRM_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_session.player_joined.connect(_on_player_joined)
	_session.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	# RpcGuard 빈도 창의 시계. 프레임당 덧셈 1회뿐이다 (성능문서 6.1).
	_now_seconds += delta


## 이 기계(멀티플레이 브랜치)가 소유한 노드인가 — WorldItem 이 자기 기계의
## NetPickup 을 찾을 때 쓴다 (헤드리스 하네스에선 한 트리에 기계가 2개다).
func owns(node: Node) -> bool:
	return _world_root.is_ancestor_of(node)


## WorldItem.interact 가 호출한다. 호스트면 즉시 권위 판정, 클라이언트면 의도 전송.
## 대상 아바타는 페이로드가 아니라 발신자에서 유도한다 (설계서 7.4) — 남의
## 인벤토리에 넣을 수 없다.
func request(item: WorldItem, who: Player) -> void:
	if multiplayer.is_server():
		_host_pickup(who, item)
		return
	request_pickup.rpc_id(RpcGuard.HOST_PEER_ID, String(_world_root.get_path_to(item)))


## 클라이언트 → 호스트: 줍기 의도. 경로만 받고 모든 사실은 호스트 월드에서 조회한다.
@rpc("any_peer", "call_remote", "reliable")
func request_pickup(item_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_pickup", sender, item_path.length(), _now_seconds):
		return
	# 명시적 스키마: 비어 있지 않고, 길이 상한 안이며, 월드 밖으로 탈출하지 않는 상대 경로.
	if item_path.is_empty() or item_path.length() > ITEM_PATH_MAX_LENGTH \
			or item_path.begins_with("/") or item_path.contains(".."):
		push_warning("NetPickup: request_pickup 스키마 위반 — 폐기 sender=%d" % sender)
		return
	var avatar: Player = _avatar_of(_session.get_player_id_for_peer(sender))
	if avatar == null:
		return
	var item: WorldItem = _world_root.get_node_or_null(item_path) as WorldItem
	if item == null:
		return  # 이미 사라진 아이템 — 동시 획득 경합에서 진 정상 경로.
	_host_pickup(avatar, item)


## 호스트 권위 판정: 존재·수량·거리를 검증하고 적용한 뒤 결과를 복제한다.
func _host_pickup(who: Player, item: WorldItem) -> void:
	if item == null or item.is_queued_for_deletion() or item.count <= 0:
		return  # 소유권 검사: 이미 다른 플레이어가 가져간 아이템은 거부 (복제 방지).
	if who == null or not is_instance_valid(who):
		return
	if who.global_position.distance_to(item.global_position) > PICKUP_MAX_DISTANCE_PX:
		push_warning("NetPickup: 사거리 밖 줍기 주장 거부 item=%s dist=%.0f" % [
			item.name, who.global_position.distance_to(item.global_position)])
		return

	# queue_free 전에 경로를 붙잡아 둔다.
	var item_path: String = String(_world_root.get_path_to(item))
	var item_id: StringName = item.item_id
	var added: int = item.apply_pickup(who)
	if added <= 0:
		return  # 인벤토리가 꽉 참 — 월드 상태 불변, 복제할 것 없음.
	if multiplayer.get_peers().size() > 0:
		confirm_pickup.rpc(item_path, String(_player_id_of(who)), String(item_id), added, item.count)


## 호스트 → 클라이언트: 획득 확정 복제. 월드 잔량과 인벤토리 복제본을 맞춘다.
@rpc("authority", "call_remote", "reliable")
func confirm_pickup(item_path: String, player_id: String, item_id: String, added: int, remaining: int) -> void:
	if not _guard.check(&"confirm_pickup", multiplayer.get_remote_sender_id(),
			item_path.length() + player_id.length() + item_id.length() + 16, _now_seconds):
		return
	if item_path.is_empty() or item_path.begins_with("/") or item_path.contains("..") \
			or added <= 0 or remaining < 0 or player_id.is_empty():
		push_warning("NetPickup: confirm_pickup 스키마 위반 — 폐기")
		return

	var item: WorldItem = _world_root.get_node_or_null(item_path) as WorldItem
	if item != null:
		item.count = remaining
		if remaining <= 0:
			item.queue_free()

	var avatar: Player = _avatar_of(StringName(player_id))
	if avatar == null:
		return
	avatar.inventory.add_item(StringName(item_id), added)
	if _event_bus != null:
		_event_bus.item_picked_up.emit(StringName(item_id), avatar)


func _on_player_joined(player_id: StringName) -> void:
	_guard.add_peer(_session.get_peer_for_player(player_id))


func _on_player_left(player_id: StringName) -> void:
	_guard.remove_peer(_session.get_peer_for_player(player_id))


func _host_id() -> StringName:
	return _session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID)


## 아바타 이름 = PlayerId 는 NetMovement 의 스폰 관례다 (scripts/net/net_movement.gd).
func _avatar_of(player_id: StringName) -> Player:
	if player_id == _host_id():
		return _host_player
	return _container.get_node_or_null(NodePath(String(player_id))) as Player


func _player_id_of(who: Player) -> StringName:
	if who == _host_player:
		return _host_id()
	return StringName(who.name)

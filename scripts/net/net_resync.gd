class_name NetResync
extends Node

## 재접속 전체 상태 재동기화 (설계서 6.3/7.3, W2-T5).
## 이탈 시 호스트가 그 PlayerId 의 상태(인벤토리·체력·출혈·위치)를 보관하고,
## 재접속 슬롯(120초, LocalSessionService) 안에 돌아오면:
##   - 아바타가 살아 있으면(30초 유예 안) 현재 권위 상태를 그대로,
##   - 아바타가 제거됐으면(30~120초 창) 보관 상태를 새 아바타에 복원한 뒤,
## 전체 스냅샷을 그 피어에게 보낸다. 인벤토리는 주기 동기화가 없어 이 스냅샷이
## 유일한 복구 경로다 — tests/net/test_net_resync.gd 가 총합 불변식을 지킨다.
## 슬롯이 만료되면 보관 상태를 폐기한다 (설계서 6.3: 미복귀 연결 종료 = 새 플레이어).

const SNAPSHOT_MAX_PER_SECOND: int = 10
const SNAPSHOT_MAX_ITEMS: int = 16
const SNAPSHOT_PAYLOAD_BYTES: int = 1024
const PLAYER_ID_MAX_LENGTH: int = 32
## 만료 청소 주기 (틱). 초당 1회면 충분하다 — 슬롯 만료 해상도는 초 단위다.
const SWEEP_INTERVAL_TICKS: int = 60

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
@export var net_movement_path: NodePath = ^"../NetMovement"

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _net_movement: NetMovement
var _guard: RpcGuard
var _now_seconds: float = 0.0
## 이탈 시점 보관 상태: player_id -> { items, health, bleeding, position, avatar_id }
var _saved_states: Dictionary = {}


func _ready() -> void:
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_net_movement = get_node(net_movement_path)
	_guard = RpcGuard.new()
	_guard.register_rule(&"apply_player_snapshot", true, SNAPSHOT_MAX_PER_SECOND, SNAPSHOT_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	# ★ 이 노드는 NetMovement 뒤에 배치한다 — player_reconnected 처리 순서가
	# '아바타 스폰(NetMovement) → 상태 복원·스냅샷(NetResync)' 이어야 한다.
	_session.player_joined.connect(_on_player_joined)
	_session.player_reconnected.connect(_on_player_reconnected)
	_session.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	_now_seconds += delta
	if Engine.get_physics_frames() % SWEEP_INTERVAL_TICKS == 0 \
			and not _saved_states.is_empty() and multiplayer.is_server():
		_sweep_expired()


## 이탈: 그 시점의 권위 상태를 보관한다. 아바타는 30초 유예 뒤 제거되지만
## 슬롯은 120초 살아 있으므로, 그 창(30~120초)의 복원 근거가 이 보관본이다.
func _on_player_left(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var avatar: Player = _avatar_of(player_id)
	if avatar == null or avatar == _host_player:
		return
	_saved_states[player_id] = {
		items = _collect_items(avatar),
		health = avatar.health.current_health,
		bleeding = avatar.health.is_bleeding,
		stats = _collect_stats(avatar),
		position = avatar.global_position,
		avatar_id = avatar.get_instance_id(),
	}


## 새 참가: 같은 PlayerId 의 옛 보관 상태가 있어도 폐기한다 (만료 후 복귀 = 새 플레이어).
func _on_player_joined(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	_saved_states.erase(player_id)


func _on_player_reconnected(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var avatar: Player = _avatar_of(player_id)
	if avatar == null:
		return
	var saved: Dictionary = _saved_states.get(player_id, {})
	_saved_states.erase(player_id)
	# 유예 안 복귀면 아바타가 이탈 때 그 노드 그대로다 — 이탈 중에도 시뮬(출혈)이
	# 진행됐으므로 보관본으로 되감지 않고 현재 권위 상태를 보낸다.
	# 아바타가 제거·재생성됐으면(인스턴스가 다르면) 보관본을 권위로 복원한다.
	if not saved.is_empty() and avatar.get_instance_id() != int(saved.avatar_id):
		_restore_into(avatar, saved)
	_send_snapshot_to(player_id, avatar)


func _restore_into(avatar: Player, saved: Dictionary) -> void:
	var items: Dictionary = saved.items
	for item_id: StringName in items:
		avatar.inventory.add_item(item_id, int(items[item_id]))
	avatar.health.apply_replicated(float(saved.health), bool(saved.bleeding))
	_restore_stats(avatar, saved.get("stats", {}))
	# 위치는 이동 검증 기준과 함께 옮긴다 — 아니면 복원 직후 클라이언트의 이동
	# 의도가 텔레포트로 오판되어 스폰 위치로 되돌아간다 (NetMovement.teleport_avatar).
	var player_id: StringName = StringName(avatar.name)
	_net_movement.teleport_avatar(player_id, saved.position)
	avatar.stats.reset_motion_baseline()


func _send_snapshot_to(player_id: StringName, avatar: Player) -> void:
	var peer: int = _session.get_peer_for_player(player_id)
	if peer <= 0:
		return
	var ids: PackedStringArray = PackedStringArray()
	var counts: PackedInt32Array = PackedInt32Array()
	var items: Dictionary = _collect_items(avatar)
	for item_id: StringName in items:
		ids.append(String(item_id))
		counts.append(int(items[item_id]))
	var stats: Dictionary = _collect_stats(avatar)
	apply_player_snapshot.rpc_id(peer, String(player_id), ids, counts,
		avatar.health.current_health, avatar.health.is_bleeding, avatar.global_position,
		float(stats.temperature), float(stats.water), float(stats.food), float(stats.fatigue))


## 호스트 → 재접속 피어: 전체 상태 스냅샷. 복제본을 비우고 권위 상태로 다시 채운다
## (부분 병합 금지 — 병합하면 이탈 전 잔존 상태와 겹쳐 아이템이 복제된다).
@rpc("authority", "call_remote", "reliable")
func apply_player_snapshot(player_id: String, item_ids: PackedStringArray,
		item_counts: PackedInt32Array, health: float, bleeding: bool, position: Vector2,
		temperature: float, water: float, food: float, fatigue: float) -> void:
	var payload: int = player_id.length() + item_ids.size() * 24 + 64
	if not _guard.check(&"apply_player_snapshot", multiplayer.get_remote_sender_id(), payload, _now_seconds):
		return
	if player_id.is_empty() or player_id.length() > PLAYER_ID_MAX_LENGTH \
			or item_ids.size() != item_counts.size() or item_ids.size() > SNAPSHOT_MAX_ITEMS \
			or not is_finite(health) or not position.is_finite() \
			or not is_finite(temperature) or not is_finite(water) \
			or not is_finite(food) or not is_finite(fatigue):
		push_warning("NetResync: apply_player_snapshot 스키마 위반 — 폐기")
		return
	var avatar: Player = _avatar_of(StringName(player_id))
	if avatar == null:
		return
	_clear_inventory(avatar)
	for index: int in range(item_ids.size()):
		if item_counts[index] > 0:
			avatar.inventory.add_item(StringName(item_ids[index]), item_counts[index])
	avatar.health.apply_replicated(health, bleeding)
	avatar.stats.apply_replicated(temperature, water, food, fatigue)
	avatar.global_position = position
	avatar.stats.reset_motion_baseline()


## 슬롯이 만료된 보관 상태를 폐기한다 (설계서 6.3: 미복귀 연결 종료).
func _sweep_expired() -> void:
	for player_id: StringName in _saved_states.keys():
		if not _session.has_reconnect_slot(player_id):
			_saved_states.erase(player_id)


func _collect_items(avatar: Player) -> Dictionary:
	var items: Dictionary = {}
	for index: int in range(avatar.inventory.slot_count):
		var slot: Dictionary = avatar.inventory.get_slot(index)
		if slot.is_empty():
			continue
		var item_id: StringName = slot["id"]
		items[item_id] = int(items.get(item_id, 0)) + int(slot["count"])
	return items


func _collect_stats(avatar: Player) -> Dictionary:
	return {
		temperature = avatar.stats.temperature,
		water = avatar.stats.water,
		food = avatar.stats.food,
		fatigue = avatar.stats.fatigue,
	}


func _restore_stats(avatar: Player, stats: Dictionary) -> void:
	if stats.is_empty():
		return
	avatar.stats.apply_replicated(float(stats.temperature), float(stats.water),
		float(stats.food), float(stats.fatigue))


func _clear_inventory(avatar: Player) -> void:
	var items: Dictionary = _collect_items(avatar)
	for item_id: StringName in items:
		avatar.inventory.remove_item(item_id, int(items[item_id]))


func _host_id() -> StringName:
	return _session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID)


## 아바타 이름 = PlayerId 는 NetMovement 의 스폰 관례다 (scripts/net/net_movement.gd).
func _avatar_of(player_id: StringName) -> Player:
	if player_id == _host_id():
		return _host_player
	return _container.get_node_or_null(NodePath(String(player_id))) as Player

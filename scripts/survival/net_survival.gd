class_name NetSurvival
extends Node

## 피해·출혈 호스트 권위 + 생존 상태 복제 (설계서 7.2/7.4, 5.2).
## 클라이언트는 부상 '의도'만 보낸다 — 주장한 피해량은 호스트 규칙
## (SurvivalConfig.remote_hurt_max_damage)으로 잘라서만 적용한다.
## 체력·출혈 상태는 10Hz 스냅샷(비신뢰 최신값)으로 복제한다.
## 피 냄새 발신은 HealthComponent 가 권위에서만 수행한다 (test_net_survival).

const DEFAULT_CONFIG: NetConfig = preload("res://resources/net/net_config.tres")

const REQUEST_MAX_PER_SECOND: int = 10
const SNAPSHOT_MAX_PER_SECOND: int = 30
const SNAPSHOT_MAX_ENTRIES: int = 8
const SNAPSHOT_ENTRY_BYTES: int = 48
const HURT_PAYLOAD_BYTES: int = 8

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
## 스냅샷 주기(snapshot_interval_ticks)를 NetMovement 와 공유한다.
@export var config: NetConfig = DEFAULT_CONFIG

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _guard: RpcGuard
var _now_seconds: float = 0.0
var _ticks: int = 0
## 스냅샷 버퍼는 재사용한다 — 매 틱 신규 배열 할당 금지 (성능문서 6.1).
var _snapshot_ids: PackedStringArray = PackedStringArray()
var _snapshot_healths: PackedFloat32Array = PackedFloat32Array()
var _snapshot_bleedings: PackedByteArray = PackedByteArray()


func _ready() -> void:
	add_to_group(&"net_survival")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_guard = RpcGuard.new()
	_guard.register_rule(&"request_hurt", false, REQUEST_MAX_PER_SECOND, HURT_PAYLOAD_BYTES)
	_guard.register_rule(&"apply_survival_snapshot", true,
		SNAPSHOT_MAX_PER_SECOND, SNAPSHOT_MAX_ENTRIES * SNAPSHOT_ENTRY_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_session.player_joined.connect(_on_player_joined)
	_session.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	_ticks += 1
	_now_seconds += delta
	if not multiplayer.is_server():
		return
	if _ticks % config.snapshot_interval_ticks == 0 and multiplayer.get_peers().size() > 0:
		_broadcast_snapshot()


## 이 기계(멀티플레이 브랜치)가 소유한 노드인가 — DebugHurt/HealTarget 이 자기
## 기계의 NetSurvival 을 찾을 때 쓴다 (헤드리스 하네스에선 한 트리에 기계가 2개다).
func owns(node: Node) -> bool:
	return get_parent().is_ancestor_of(node)


## 부상 의도 (DebugHurt 가 호출). 호스트면 즉시 권위 판정, 클라이언트면 의도 전송.
func request_hurt_for(player: Player, claimed_damage: float) -> void:
	if multiplayer.is_server():
		_host_hurt(player, claimed_damage)
		return
	request_hurt.rpc_id(RpcGuard.HOST_PEER_ID, claimed_damage)


## 클라이언트 → 호스트: 부상 의도. 대상은 페이로드가 아니라 발신자에서 유도한다
## (설계서 7.4) — 남을 다치게 할 수 없다.
@rpc("any_peer", "call_remote", "reliable")
func request_hurt(claimed_damage: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_hurt", sender, HURT_PAYLOAD_BYTES, _now_seconds):
		return
	_host_hurt(_avatar_of(_session.get_player_id_for_peer(sender)), claimed_damage)


## 호스트 권위 판정: 주장값을 그대로 믿지 않고 호스트 규칙 상한으로 자른다 (설계서 7.4).
func _host_hurt(player: Player, claimed_damage: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not is_finite(claimed_damage) or claimed_damage <= 0.0:
		return
	var amount: float = minf(claimed_damage, player.health.config.remote_hurt_max_damage)
	player.health.take_damage(amount, &"debug")
	player.health.start_bleeding()


## 호스트 → 클라이언트: 체력·출혈 스냅샷 (비신뢰 최신값, 설계서 7.2).
@rpc("authority", "call_remote", "unreliable_ordered")
func apply_survival_snapshot(ids: PackedStringArray, healths: PackedFloat32Array, bleedings: PackedByteArray) -> void:
	if not _guard.check(&"apply_survival_snapshot", multiplayer.get_remote_sender_id(),
			ids.size() * SNAPSHOT_ENTRY_BYTES, _now_seconds):
		return
	if ids.size() != healths.size() or ids.size() != bleedings.size() \
			or ids.size() > SNAPSHOT_MAX_ENTRIES:
		push_warning("NetSurvival: apply_survival_snapshot 스키마 위반 — 폐기")
		return
	for index: int in range(ids.size()):
		var health_value: float = healths[index]
		if not is_finite(health_value):
			continue
		var avatar: Player = _avatar_of(StringName(ids[index]))
		if avatar == null:
			continue
		avatar.health.apply_replicated(health_value, bleedings[index] != 0)


func _broadcast_snapshot() -> void:
	var count: int = 1 + _container.get_child_count()
	if _snapshot_ids.size() != count:
		_snapshot_ids.resize(count)
		_snapshot_healths.resize(count)
		_snapshot_bleedings.resize(count)
	_fill_snapshot_entry(0, _host_id(), _host_player)
	var index: int = 1
	for child: Node in _container.get_children():
		var avatar: Player = child as Player
		if avatar == null:
			continue
		_fill_snapshot_entry(index, StringName(avatar.name), avatar)
		index += 1
	if index != count:
		_snapshot_ids.resize(index)
		_snapshot_healths.resize(index)
		_snapshot_bleedings.resize(index)
	apply_survival_snapshot.rpc(_snapshot_ids, _snapshot_healths, _snapshot_bleedings)


func _fill_snapshot_entry(index: int, player_id: StringName, avatar: Player) -> void:
	_snapshot_ids[index] = String(player_id)
	_snapshot_healths[index] = avatar.health.current_health
	_snapshot_bleedings[index] = 1 if avatar.health.is_bleeding else 0


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

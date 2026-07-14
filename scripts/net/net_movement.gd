class_name NetMovement
extends Node

## 2인 이동 동기화 + 호스트 권한 검증 골격 (설계서 7.2/7.4, 9.3).
## 클라이언트는 '의도'(자신이 예측한 위치)만 보낸다. 호스트가 텔레포트 검사로
## 검증해 최종 위치를 권위적으로 확정하고, 비신뢰 스냅샷(10Hz)으로 복제한다.
## 싱글플레이 = 로컬 호스트 한 명인 동일 흐름 (peer 없음 → 네트워크 활동 0).
##
## 이후 태스크(공룡 AI·아이템·피해 복제)는 이 검증 골격(RpcGuard + 권위 확정
## → 복제) 위에 얹는다. 백엔드는 SessionService 뒤에 있어 여기엔 ENet 이 없다.

const DEFAULT_CONFIG: NetConfig = preload("res://resources/net/net_config.tres")

## 고정 스키마 의도(Vector2)의 페이로드 추정치 — 상한 검사용 (설계서 7.4).
const INTENT_PAYLOAD_BYTES: int = 16
const SNAPSHOT_ENTRY_BYTES: int = 32
const SPAWN_ID_MAX_LENGTH: int = 32
const SNAPSHOT_MAX_ENTRIES: int = 8
## 스폰·스냅샷 같은 저빈도 호스트 RPC 의 초당 상한 (프로토콜 내부 값).
const CONTROL_RPC_MAX_PER_SECOND: int = 30

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
@export var avatar_scene: PackedScene
@export var config: NetConfig = DEFAULT_CONFIG

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _authority: MovementAuthority
var _guard: RpcGuard
var _avatars: Dictionary = {}
var _local_avatar: Player = null
var _last_sent_position: Vector2 = Vector2.INF
var _last_intent_ticks: Dictionary = {}
var _ticks: int = 0
var _now_seconds: float = 0.0
var _tick_delta: float = 1.0 / 60.0
var _snapshot_ids: PackedStringArray = PackedStringArray()
var _snapshot_positions: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_tick_delta = 1.0 / float(Engine.physics_ticks_per_second)
	_authority = MovementAuthority.new(config.move_tolerance, config.min_move_allowance_px)
	_guard = RpcGuard.new()
	_guard.register_rule(&"submit_move_intent", false,
		config.intent_max_per_second, config.intent_max_payload_bytes)
	_guard.register_rule(&"spawn_avatar", true,
		CONTROL_RPC_MAX_PER_SECOND, config.spawn_max_payload_bytes)
	_guard.register_rule(&"despawn_avatar", true,
		CONTROL_RPC_MAX_PER_SECOND, config.spawn_max_payload_bytes)
	_guard.register_rule(&"apply_snapshot", true,
		CONTROL_RPC_MAX_PER_SECOND, config.snapshot_max_payload_bytes)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_avatars[_session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID)] = _host_player
	_session.player_joined.connect(_on_player_joined)
	_session.player_left.connect(_on_player_left)
	_session.session_ended.connect(_on_session_ended)


func _physics_process(delta: float) -> void:
	_ticks += 1
	_now_seconds += delta
	if multiplayer.is_server():
		if _ticks % config.snapshot_interval_ticks == 0 and multiplayer.get_peers().size() > 0:
			_broadcast_snapshot()
	elif _local_avatar != null:
		# 이동·방향은 비신뢰 최신값 전송 (설계서 7.2). 멈춰 있으면 보내지 않는다.
		var position: Vector2 = _local_avatar.global_position
		if position.distance_squared_to(_last_sent_position) > 0.01:
			_last_sent_position = position
			submit_move_intent.rpc_id(RpcGuard.HOST_PEER_ID, position)


func get_move_violation_count(player_id: StringName) -> int:
	return _authority.get_violation_count(player_id)


## 클라이언트 → 호스트: 이동 의도. 대상 아바타는 페이로드가 아니라
## 발신자에서 유도한다 — 남의 아바타는 절대 움직일 수 없다 (설계서 7.4).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_move_intent(claimed_position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"submit_move_intent", sender, INTENT_PAYLOAD_BYTES, _now_seconds):
		return
	var player_id: StringName = _session.get_player_id_for_peer(sender)
	var avatar: Player = _avatars.get(player_id)
	if avatar == null:
		return
	var elapsed_ticks: int = _ticks - int(_last_intent_ticks.get(sender, _ticks))
	var elapsed: float = minf(float(elapsed_ticks) * _tick_delta, config.intent_elapsed_cap_seconds)
	_last_intent_ticks[sender] = _ticks
	avatar.global_position = _authority.submit(
		player_id, claimed_position, elapsed, avatar.config.run_speed)


## 호스트 → 클라이언트: 권위 스폰. 발신자·스키마 검사 후 수용 (설계서 7.4).
@rpc("authority", "call_remote", "reliable")
func spawn_avatar(player_id: String, controller_peer_id: int, position: Vector2) -> void:
	if not _guard.check(&"spawn_avatar", multiplayer.get_remote_sender_id(),
			player_id.length() + 24, _now_seconds):
		return
	if player_id.is_empty() or player_id.length() > SPAWN_ID_MAX_LENGTH or not position.is_finite():
		push_warning("NetMovement: spawn_avatar 스키마 위반 — 폐기")
		return
	if _avatars.has(StringName(player_id)):
		return
	_spawn(StringName(player_id), controller_peer_id, position)


## 호스트 → 클라이언트: 권위 제거.
@rpc("authority", "call_remote", "reliable")
func despawn_avatar(player_id: String) -> void:
	if not _guard.check(&"despawn_avatar", multiplayer.get_remote_sender_id(),
			player_id.length() + 8, _now_seconds):
		return
	_despawn(StringName(player_id))


## 호스트 → 클라이언트: 위치 스냅샷 (비신뢰 최신값).
@rpc("authority", "call_remote", "unreliable")
func apply_snapshot(ids: PackedStringArray, positions: PackedVector2Array) -> void:
	if not _guard.check(&"apply_snapshot", multiplayer.get_remote_sender_id(),
			ids.size() * SNAPSHOT_ENTRY_BYTES, _now_seconds):
		return
	if ids.size() != positions.size() or ids.size() > SNAPSHOT_MAX_ENTRIES:
		push_warning("NetMovement: apply_snapshot 스키마 위반 — 폐기")
		return
	for index: int in range(ids.size()):
		var position: Vector2 = positions[index]
		if not position.is_finite():
			continue
		var avatar: Player = _avatars.get(StringName(ids[index]))
		if avatar == null:
			continue
		if avatar == _local_avatar:
			# 자기 아바타는 서버 확정에서 크게 벗어났을 때만 보정한다
			# (호스트가 의도를 거부한 경우 되돌리기).
			if avatar.global_position.distance_to(position) > config.correction_snap_px:
				avatar.global_position = position
				_last_sent_position = position
		else:
			avatar.global_position = position


func _on_player_joined(player_id: StringName) -> void:
	# 스폰 권한은 호스트에게만 있다 (설계서 7.2). 클라이언트는 RPC 로 받는다.
	if not multiplayer.is_server():
		return
	var peer: int = _session.get_peer_for_player(player_id)
	_guard.add_peer(peer)
	_last_intent_ticks[peer] = _ticks
	var spawn_position: Vector2 = _host_player.global_position + config.client_spawn_offset
	_spawn(player_id, peer, spawn_position)
	spawn_avatar.rpc(String(player_id), peer, spawn_position)


func _on_player_left(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	# ponytail: 설계서 7.3 의 '30초 제자리 잔류'와 120초 재접속 슬롯은 다음 태스크 —
	# 그때 이 즉시 제거를 유예 제거로 바꾼다. 슬롯 식별자는 이미 PlayerId 다.
	var peer: int = _session.get_peer_for_player(player_id)
	_guard.remove_peer(peer)
	_last_intent_ticks.erase(peer)
	_despawn(player_id)
	despawn_avatar.rpc(String(player_id))


func _on_session_ended() -> void:
	# 세션 종료(자발적 이탈·호스트 이탈): 스폰된 아바타를 전부 정리한다.
	for player_id: StringName in _avatars.keys():
		if _avatars[player_id] != _host_player:
			_despawn(player_id)


func _spawn(player_id: StringName, controller_peer_id: int, position: Vector2) -> void:
	var avatar: Player = avatar_scene.instantiate()
	avatar.name = String(player_id)
	avatar.controller_peer_id = controller_peer_id
	_container.add_child(avatar)
	avatar.global_position = position
	_avatars[player_id] = avatar
	_authority.register_player(player_id, position)
	if controller_peer_id == multiplayer.get_unique_id():
		_local_avatar = avatar
		_last_sent_position = position
		var camera: Camera2D = avatar.get_node_or_null("Camera2D")
		if camera != null:
			camera.make_current()


func _despawn(player_id: StringName) -> void:
	var avatar: Player = _avatars.get(player_id)
	if avatar == null or avatar == _host_player:
		return
	_avatars.erase(player_id)
	_authority.unregister_player(player_id)
	if avatar == _local_avatar:
		_local_avatar = null
	avatar.queue_free()


func _broadcast_snapshot() -> void:
	var count: int = _avatars.size()
	if _snapshot_ids.size() != count:
		_snapshot_ids.resize(count)
		_snapshot_positions.resize(count)
	var index: int = 0
	for player_id: StringName in _avatars:
		_snapshot_ids[index] = String(player_id)
		_snapshot_positions[index] = (_avatars[player_id] as Player).global_position
		index += 1
	apply_snapshot.rpc(_snapshot_ids, _snapshot_positions)

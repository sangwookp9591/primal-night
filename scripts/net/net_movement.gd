class_name NetMovement
extends Node

## 2인 이동 동기화 + 호스트 권한 검증 골격 (설계서 7.2/7.4, 9.3).
## 클라이언트는 '의도'(자신이 예측한 위치)만 보낸다. 호스트가 텔레포트 검사로
## 검증해 최종 위치를 권위적으로 확정하고, 비신뢰 스냅샷(10Hz)으로 복제한다.
## 싱글플레이 = 로컬 호스트 한 명인 동일 흐름 (peer 없음 → 네트워크 활동 0).
##
## 이후 태스크(공룡 AI·아이템·피해 복제)는 이 검증 골격(RpcGuard + 권위 확정
## → 복제) 위에 얹는다. 전송 백엔드는 SessionService 뒤에 캡슐화되어 있다.

const DEFAULT_CONFIG: NetConfig = preload("res://resources/net/net_config.tres")

## 고정 스키마 의도(Vector2 + 자세 int)의 페이로드 추정치 — 상한 검사용 (설계서 7.4).
const INTENT_PAYLOAD_BYTES: int = 20
const SNAPSHOT_ENTRY_BYTES: int = 32
const SPAWN_ID_MAX_LENGTH: int = 32
const SNAPSHOT_MAX_ENTRIES: int = 8
## 스폰·스냅샷 같은 저빈도 호스트 RPC 의 초당 상한 (프로토콜 내부 값).
const CONTROL_RPC_MAX_PER_SECOND: int = 30
const DISCONNECT_DESPAWN_SECONDS: float = 30.0

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
var _pending_despawn_seconds: Dictionary = {}


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
	# 참가·재접속·이탈에 따른 발신자 명부 유지는 RpcGuard 가 소유한다 (W2-T5).
	# 아래 구독들은 스폰·제거 등 이 노드 고유 작업만 담당한다.
	_guard.watch_session(_session)
	_avatars[_session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID)] = _host_player
	_session.player_joined.connect(_on_player_joined)
	_session.player_reconnected.connect(_on_player_reconnected)
	_session.player_left.connect(_on_player_left)
	_session.session_ended.connect(_on_session_ended)


func _physics_process(delta: float) -> void:
	_ticks += 1
	_now_seconds += delta
	_session.tick_reconnect_slots(delta)
	if multiplayer.is_server():
		_tick_pending_despawns(delta)
		if _ticks % config.snapshot_interval_ticks == 0 and multiplayer.get_peers().size() > 0:
			_broadcast_snapshot()
	elif _local_avatar != null:
		# 이동·방향은 비신뢰 최신값 전송 (설계서 7.2). 멈춰 있으면 보내지 않는다.
		# 자세(웅크림/걷기/달리기)도 함께 보낸다 — 호스트가 실측 속도로 교차검증한다
		# (설계서 7.4, 은신 소음이 원격 아바타에도 적용되려면 필수).
		var position: Vector2 = _local_avatar.global_position
		if position.distance_squared_to(_last_sent_position) > 0.01:
			_last_sent_position = position
			submit_move_intent.rpc_id(RpcGuard.HOST_PEER_ID, position, _local_avatar.stance)


func get_move_violation_count(player_id: StringName) -> int:
	return _authority.get_violation_count(player_id)


## 호스트 권위 순간이동 (재접속 상태 복원 등, W2-T5). 아바타 위치와 함께
## 이동 검증 기준(MovementAuthority)도 옮긴다 — 기준을 같이 옮기지 않으면
## 복원 직후의 정직한 이동 의도가 텔레포트로 오판·거부되어 위치가 되돌아간다.
func teleport_avatar(player_id: StringName, position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var avatar: Player = _avatars.get(player_id)
	if avatar == null:
		return
	avatar.global_position = position
	_reset_survival_motion_baseline(avatar)
	_authority.register_player(player_id, position)


## 클라이언트 → 호스트: 이동 의도 + 주장 자세. 대상 아바타는 페이로드가 아니라
## 발신자에서 유도한다 — 남의 아바타는 절대 움직일 수 없다 (설계서 7.4).
## 자세는 그대로 믿지 않는다: 실측 속도가 주장 자세의 허용 속도를 넘으면
## 실제 속도가 설명되는 가장 조용한 자세로 강등한다 (교차검증, MovementAuthority 관례).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_move_intent(claimed_position: Vector2, claimed_stance: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"submit_move_intent", sender, INTENT_PAYLOAD_BYTES, _now_seconds):
		return
	var player_id: StringName = _session.get_player_id_for_peer(sender)
	var avatar: Player = _avatars.get(player_id)
	if avatar == null:
		return
	if claimed_stance < 0 or claimed_stance >= Player.Stance.size():
		# 스키마 위반 — 조용한 쪽으로 위조할 수 없게 가장 시끄러운 자세로 취급한다.
		claimed_stance = Player.Stance.RUN
	var elapsed_ticks: int = _ticks - int(_last_intent_ticks.get(sender, _ticks))
	var elapsed: float = minf(float(elapsed_ticks) * _tick_delta, config.intent_elapsed_cap_seconds)
	_last_intent_ticks[sender] = _ticks
	var previous_position: Vector2 = _authority.get_position(player_id)
	avatar.global_position = _authority.submit(
		player_id, claimed_position, elapsed, avatar.config.run_speed)
	var actual_speed: float = 0.0
	if elapsed > 0.0:
		actual_speed = previous_position.distance_to(avatar.global_position) / elapsed
	avatar.last_validated_stance = _validate_stance(claimed_stance, actual_speed, avatar)


## 주장한 자세가 실측 속도로 정당화되는지 본다. 조용한 자세(웅크림)를 주장하며
## 실제로는 더 빨리 움직였으면, 그 속도를 설명하는 다음 단계 자세로 강등한다
## (웅크림→걷기→달리기 순 — 달리기보다 시끄러운 자세는 없어 더 강등할 곳이 없다).
func _validate_stance(claimed_stance: int, actual_speed: float, avatar: Player) -> int:
	var stance: int = claimed_stance
	if stance == Player.Stance.CROUCH \
			and actual_speed > avatar.max_speed_for_stance(Player.Stance.CROUCH) * config.move_tolerance:
		stance = Player.Stance.WALK
	if stance == Player.Stance.WALK \
			and actual_speed > avatar.max_speed_for_stance(Player.Stance.WALK) * config.move_tolerance:
		stance = Player.Stance.RUN
	return stance


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
	_last_intent_ticks[peer] = _ticks
	var spawn_position: Vector2 = _host_player.global_position + config.client_spawn_offset
	_spawn(player_id, peer, spawn_position)
	spawn_avatar.rpc(String(player_id), peer, spawn_position)


func _on_player_left(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var peer: int = _session.get_peer_for_player(player_id)
	_last_intent_ticks.erase(peer)
	if _avatars.has(player_id):
		_pending_despawn_seconds[player_id] = DISCONNECT_DESPAWN_SECONDS


func _on_player_reconnected(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var peer: int = _session.get_peer_for_player(player_id)
	_last_intent_ticks[peer] = _ticks
	_pending_despawn_seconds.erase(player_id)
	var avatar: Player = _avatars.get(player_id)
	if avatar == null:
		_on_player_joined(player_id)
		return
	avatar.controller_peer_id = peer
	spawn_avatar.rpc_id(peer, String(player_id), peer, avatar.global_position)


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
	_reset_survival_motion_baseline(avatar)
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
	_pending_despawn_seconds.erase(player_id)
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


func _tick_pending_despawns(delta: float) -> void:
	for player_id: StringName in _pending_despawn_seconds.keys():
		var remaining: float = float(_pending_despawn_seconds[player_id]) - delta
		if remaining > 0.0:
			_pending_despawn_seconds[player_id] = remaining
			continue
		_despawn(player_id)
		despawn_avatar.rpc(String(player_id))


func _reset_survival_motion_baseline(avatar: Player) -> void:
	if avatar != null and avatar.stats != null:
		avatar.stats.reset_motion_baseline()

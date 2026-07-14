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
	_guard.register_rule(&"request_heal_start", false, REQUEST_MAX_PER_SECOND, HEAL_PAYLOAD_BYTES)
	_guard.register_rule(&"request_heal_cancel", false, REQUEST_MAX_PER_SECOND, HEAL_PAYLOAD_BYTES)
	_guard.register_rule(&"request_heal_commit", false, REQUEST_MAX_PER_SECOND, HEAL_PAYLOAD_BYTES)
	_guard.register_rule(&"apply_heal_lock", true, SNAPSHOT_MAX_PER_SECOND, HEAL_PAYLOAD_BYTES)
	_guard.register_rule(&"apply_heal_result", true, SNAPSHOT_MAX_PER_SECOND, HEAL_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_session.player_joined.connect(_on_player_joined)
	# 재접속 피어는 새 peer id 를 받는다 — 재등록하지 않으면 unknown_sender 로
	# 거부되어 재접속 후 부상·치료 의도가 죽는다 (tests/net/test_net_resync.gd, W2-T5).
	_session.player_reconnected.connect(_on_player_joined)
	_session.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	_ticks += 1
	_now_seconds += delta
	if not multiplayer.is_server():
		return
	if _ticks % config.snapshot_interval_ticks == 0:
		if not _heal_sessions.is_empty():
			_validate_heal_sessions()
		if multiplayer.get_peers().size() > 0:
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


## --- 붕대 치료 세션 (설계서 5.2): 호스트가 세션·홀드 시간·붕대·거리를 검증한다 ---

## 치료 검증 거리 (px): 상호작용 손 48 + 치료 지점 20 + 스냅샷 지연 여유 (프로토콜 슬랙).
const HEAL_MAX_DISTANCE_PX: float = 128.0
## 홀드 시간 검증 여유 — 시작 통지와 커밋의 왕복 지연 차이를 흡수한다.
const HEAL_HOLD_SLACK_SECONDS: float = 0.25
const PLAYER_ID_MAX_LENGTH: int = 32
const HEAL_PAYLOAD_BYTES: int = 80

## healer_id(StringName) -> { patient_id: StringName, start_ticks: int }
var _heal_sessions: Dictionary = {}


## 홀드 시작 (HealTarget 이 호출). 호스트가 세션을 열고 양쪽 이동을 잠근다.
func notify_heal_hold_started(healer: Player, patient: Player) -> void:
	if multiplayer.is_server():
		_host_heal_start(_player_id_of(healer), _player_id_of(patient))
		return
	request_heal_start.rpc_id(RpcGuard.HOST_PEER_ID, String(_player_id_of(patient)))


## 홀드 종료 (완료·취소 무관하게 항상 1회). 커밋이 먼저 처리됐으면 no-op.
func notify_heal_hold_ended(healer: Player) -> void:
	if multiplayer.is_server():
		_host_heal_cancel(_player_id_of(healer))
		return
	request_heal_cancel.rpc_id(RpcGuard.HOST_PEER_ID)


## 홀드 완료 (HealTarget.interact 가 호출). 호스트가 재검증 후 확정한다.
func request_heal_commit_for(healer: Player, patient: Player) -> void:
	if multiplayer.is_server():
		_host_heal_commit(_player_id_of(healer), _player_id_of(patient))
		return
	request_heal_commit.rpc_id(RpcGuard.HOST_PEER_ID, String(_player_id_of(patient)))


## 클라이언트 → 호스트: 치료 시작 의도. 치료자는 발신자에서 유도한다 (설계서 7.4).
@rpc("any_peer", "call_remote", "reliable")
func request_heal_start(patient_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_heal_start", sender, patient_id.length(), _now_seconds):
		return
	if patient_id.is_empty() or patient_id.length() > PLAYER_ID_MAX_LENGTH:
		push_warning("NetSurvival: request_heal_start 스키마 위반 — 폐기")
		return
	_host_heal_start(_session.get_player_id_for_peer(sender), StringName(patient_id))


@rpc("any_peer", "call_remote", "reliable")
func request_heal_cancel() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_heal_cancel", sender, 0, _now_seconds):
		return
	_host_heal_cancel(_session.get_player_id_for_peer(sender))


@rpc("any_peer", "call_remote", "reliable")
func request_heal_commit(patient_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_heal_commit", sender, patient_id.length(), _now_seconds):
		return
	if patient_id.is_empty() or patient_id.length() > PLAYER_ID_MAX_LENGTH:
		push_warning("NetSurvival: request_heal_commit 스키마 위반 — 폐기")
		return
	_host_heal_commit(_session.get_player_id_for_peer(sender), StringName(patient_id))


## 호스트 → 클라이언트: 치료 중 이동 잠금 복제 (설계서 5.2: 양쪽 이동 제한).
@rpc("authority", "call_remote", "reliable")
func apply_heal_lock(healer_id: String, patient_id: String, locked: bool) -> void:
	if not _guard.check(&"apply_heal_lock", multiplayer.get_remote_sender_id(),
			healer_id.length() + patient_id.length() + 1, _now_seconds):
		return
	_apply_heal_lock_local(StringName(healer_id), StringName(patient_id), locked)


## 호스트 → 클라이언트: 치료 확정 복제 (붕대 소비 + 지혈).
@rpc("authority", "call_remote", "reliable")
func apply_heal_result(healer_id: String, patient_id: String) -> void:
	if not _guard.check(&"apply_heal_result", multiplayer.get_remote_sender_id(),
			healer_id.length() + patient_id.length(), _now_seconds):
		return
	var healer: Player = _avatar_of(StringName(healer_id))
	if healer != null:
		healer.inventory.remove_item(HealTarget.BANDAGE_ID, 1)
	var patient: Player = _avatar_of(StringName(patient_id))
	if patient != null:
		patient.health.stop_bleeding()


func _host_heal_start(healer_id: StringName, patient_id: StringName) -> void:
	if _heal_sessions.has(healer_id):
		return
	if not _heal_valid(healer_id, patient_id):
		return
	_heal_sessions[healer_id] = { patient_id = patient_id, start_ticks = _ticks }
	_set_heal_lock(healer_id, patient_id, true)


func _host_heal_cancel(healer_id: StringName) -> void:
	var session: Dictionary = _heal_sessions.get(healer_id, {})
	if session.is_empty():
		return
	_heal_sessions.erase(healer_id)
	_set_heal_lock(healer_id, session.patient_id, false)


func _host_heal_commit(healer_id: StringName, patient_id: StringName) -> void:
	var session: Dictionary = _heal_sessions.get(healer_id, {})
	if session.is_empty() or session.patient_id != patient_id:
		return  # 세션 없는 커밋 — 변조이거나 이미 취소된 경합.
	var patient: Player = _avatar_of(patient_id)
	if patient == null or not _heal_valid(healer_id, patient_id):
		_host_heal_cancel(healer_id)  # 조건이 깨졌다 (붕대 소실·사망 등) — 세션 정리.
		return
	# 홀드 시간은 호스트 시계로 검증한다 — 즉시 커밋 변조 차단 (설계서 7.4).
	var elapsed: float = float(_ticks - int(session.start_ticks)) / float(Engine.physics_ticks_per_second)
	var required: float = patient.health.config.bandage_hold_seconds - HEAL_HOLD_SLACK_SECONDS
	if elapsed < required:
		push_warning("NetSurvival: 홀드 미달 커밋 거부 (%.2fs < %.2fs) — 변조 의심" % [elapsed, required])
		return
	var healer: Player = _avatar_of(healer_id)
	healer.inventory.remove_item(HealTarget.BANDAGE_ID, 1)
	patient.health.stop_bleeding()
	_heal_sessions.erase(healer_id)
	_set_heal_lock(healer_id, patient_id, false)
	if multiplayer.get_peers().size() > 0:
		apply_heal_result.rpc(String(healer_id), String(patient_id))


## 호스트 재검증: 존재·출혈·생존·붕대·거리 (설계서 7.2: 거리·소유권·상태 검증).
func _heal_valid(healer_id: StringName, patient_id: StringName) -> bool:
	var healer: Player = _avatar_of(healer_id)
	var patient: Player = _avatar_of(patient_id)
	if healer == null or patient == null:
		return false
	if not patient.health.is_bleeding or not patient.health.is_alive():
		return false
	if not healer.inventory.has_item(HealTarget.BANDAGE_ID, 1):
		return false
	return healer.global_position.distance_to(patient.global_position) <= HEAL_MAX_DISTANCE_PX


## 치료 중 대상이 죽거나 조건이 깨지면 세션을 끊고 잠금을 푼다 (설계서 5.2 경계).
func _validate_heal_sessions() -> void:
	for healer_id: StringName in _heal_sessions.keys():
		if not _heal_valid(healer_id, _heal_sessions[healer_id].patient_id):
			_host_heal_cancel(healer_id)


func _set_heal_lock(healer_id: StringName, patient_id: StringName, locked: bool) -> void:
	_apply_heal_lock_local(healer_id, patient_id, locked)
	if multiplayer.get_peers().size() > 0:
		apply_heal_lock.rpc(String(healer_id), String(patient_id), locked)


func _apply_heal_lock_local(healer_id: StringName, patient_id: StringName, locked: bool) -> void:
	var healer: Player = _avatar_of(healer_id)
	if healer != null:
		healer.movement_locked = locked
	var patient: Player = _avatar_of(patient_id)
	if patient != null:
		patient.movement_locked = locked


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
	if not multiplayer.is_server():
		return
	# 치료자 또는 환자가 이탈하면 그 치료 세션을 끊는다 (설계서 5.2/7.3 경계).
	# 이탈 아바타는 30초 유예 제거(NetMovement)라 노드 존재만으론 걸러지지 않는다.
	_host_heal_cancel(player_id)
	for healer_id: StringName in _heal_sessions.keys():
		if _heal_sessions[healer_id].patient_id == player_id:
			_host_heal_cancel(healer_id)


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

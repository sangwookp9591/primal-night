class_name NetButcher
extends Node

## 사체 해체 호스트 권위 (W5-T2, 정본 §14.4 / 설계서 7.2·7.4).
##
## 클라이언트는 '해체 의도'(사체 경로)만 보낸다 — 산출 아이템·수량은 페이로드에 없어
## 조작할 수 없다. 호스트가 자기 월드의 실제 Carcass 를 조회해 존재·거리·홀드 시간·
## 잔여 구간을 검증하고 `yield_mask` 를 확정한 뒤 결과를 신뢰 전송으로 복제한다.
##
## 이 노드가 지키는 불변식 (tests/world/test_net_butcher.gd):
##   1. 구간 bit 는 정확히 한 번만 선다 (동시 해체·재접속에서도).
##   2. 홀드 시간을 채우지 않은 커밋은 거부한다 (즉시 완료 변조 차단).
##   3. 산출을 전부 넣을 수 없으면 bit 를 소모하지 않는다 (조용한 증발 금지).

## 해체 검증 거리 (px): 사체 유지 거리 72 + 10Hz 위치 스냅샷 지연 여유.
## 게임 규칙이 아니라 변조 방지 슬랙이라 프로토콜 상수다 (NetPickup 관례).
const BUTCHER_MAX_DISTANCE_PX: float = 128.0
## 홀드 시간 검증 여유. 네트워크 지연·프레임 경계로 클라이언트가 살짝 먼저
## 커밋할 수 있다 (NetSurvival.HEAL_HOLD_SLACK_SECONDS 와 같은 이유).
const BUTCHER_HOLD_SLACK_SECONDS: float = 0.25

const CARCASS_PATH_MAX_LENGTH: int = 128
const PLAYER_ID_MAX_LENGTH: int = 32
const REQUEST_MAX_PER_SECOND: int = 10
const CONFIRM_MAX_PER_SECOND: int = 30
const CONFIRM_PAYLOAD_BYTES: int = 512
const SNAPSHOT_MAX_PER_SECOND: int = 10
const SNAPSHOT_MAX_CARCASSES: int = 64
const SNAPSHOT_PAYLOAD_BYTES: int = 8192

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
## 사체 경로 해석 기준. 양쪽 기계가 같은 씬을 로드하므로 상대 경로가 일치한다.
@export var world_root_path: NodePath = ^".."

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _world_root: Node
var _guard: RpcGuard
var _now_seconds: float = 0.0
var _ticks: int = 0
## 진행 중인 해체 홀드: "player_id|carcass_path" -> { start_ticks }
var _hold_sessions: Dictionary = {}


func _ready() -> void:
	add_to_group(&"net_butcher")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_world_root = get_node(world_root_path)
	_guard = RpcGuard.new()
	_guard.register_rule(&"request_butcher_start", false, REQUEST_MAX_PER_SECOND, CARCASS_PATH_MAX_LENGTH + 16)
	_guard.register_rule(&"request_butcher_cancel", false, REQUEST_MAX_PER_SECOND, CARCASS_PATH_MAX_LENGTH + 16)
	_guard.register_rule(&"request_butcher_commit", false, REQUEST_MAX_PER_SECOND, CARCASS_PATH_MAX_LENGTH + 16)
	_guard.register_rule(&"request_drag_toggle", false, REQUEST_MAX_PER_SECOND, CARCASS_PATH_MAX_LENGTH + 16)
	_guard.register_rule(&"confirm_butcher_stage", true, CONFIRM_MAX_PER_SECOND, CONFIRM_PAYLOAD_BYTES)
	_guard.register_rule(&"confirm_drag_state", true, CONFIRM_MAX_PER_SECOND, CONFIRM_PAYLOAD_BYTES)
	_guard.register_rule(&"confirm_drag_position", true, CONFIRM_MAX_PER_SECOND, CONFIRM_PAYLOAD_BYTES)
	_guard.register_rule(&"apply_carcass_snapshot", true, SNAPSHOT_MAX_PER_SECOND, SNAPSHOT_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_guard.watch_session(_session)
	# 사체는 월드 상태라 재접속 복원을 여기서 소유한다 (NetResync 는 플레이어 상태 담당).
	# 아바타 스폰 순서에 기대지 않는다 — 사체는 씬에 이미 있고 아바타와 무관하다.
	_session.player_reconnected.connect(send_world_snapshot_to)


func _physics_process(delta: float) -> void:
	# RpcGuard 빈도 창의 시계 + 홀드 시간 검증용 호스트 틱. 프레임당 덧셈 2회뿐이다.
	_now_seconds += delta
	_ticks += 1


## 이 기계(멀티플레이 브랜치)가 소유한 노드인가 — Carcass 가 자기 기계의
## NetButcher 를 찾을 때 쓴다 (헤드리스 하네스에선 한 트리에 기계가 2개다).
func owns(node: Node) -> bool:
	return _world_root.is_ancestor_of(node)


# --- Carcass 가 부르는 진입점 -------------------------------------------------

func notify_butcher_hold_started(who: Player, carcass: Carcass) -> void:
	if multiplayer.is_server():
		_host_hold_start(_player_id_of(who), _path_of(carcass))
		return
	request_butcher_start.rpc_id(RpcGuard.HOST_PEER_ID, _path_of(carcass))


## 홀드 종료 (완료·취소 무관하게 항상 1회). 커밋이 먼저 처리됐으면 no-op.
func notify_butcher_hold_ended(who: Player, carcass: Carcass) -> void:
	if multiplayer.is_server():
		_hold_sessions.erase(_session_key(_player_id_of(who), _path_of(carcass)))
		return
	request_butcher_cancel.rpc_id(RpcGuard.HOST_PEER_ID, _path_of(carcass))


func request_stage_commit_for(who: Player, carcass: Carcass) -> void:
	if multiplayer.is_server():
		_host_stage_commit(_player_id_of(who), _path_of(carcass))
		return
	request_butcher_commit.rpc_id(RpcGuard.HOST_PEER_ID, _path_of(carcass))


func request_drag_toggle_for(who: Player, carcass: Carcass) -> void:
	if multiplayer.is_server():
		_host_drag_toggle(_player_id_of(who), _path_of(carcass))
		return
	request_drag_toggle.rpc_id(RpcGuard.HOST_PEER_ID, _path_of(carcass))


func replicate_drag_state(carcass: Carcass, who: Player) -> void:
	if not multiplayer.is_server() or multiplayer.get_peers().is_empty():
		return
	confirm_drag_state.rpc(_path_of(carcass), String(_player_id_of(who)) if who != null else "",
		carcass.global_position)


func replicate_drag_position(carcass: Carcass) -> void:
	if not multiplayer.is_server() or multiplayer.get_peers().is_empty():
		return
	confirm_drag_position.rpc(_path_of(carcass), carcass.global_position)


## 재접속 월드 스냅샷: 이미 확정된 사체 구간을 그 피어에 복원한다.
## 플레이어 상태(NetResync)와 달리 사체는 월드 상태라 여기서 보낸다 — 계획 §6 대로
## 구조를 키우지 않고 사체 배열 하나만 보낸다.
func send_world_snapshot_to(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var peer: int = _session.get_peer_for_player(player_id)
	if peer <= 0:
		return
	var paths: PackedStringArray = PackedStringArray()
	var masks: PackedInt32Array = PackedInt32Array()
	for node: Node in get_tree().get_nodes_in_group(&"carcass"):
		var carcass: Carcass = node as Carcass
		if carcass == null or not owns(carcass) or carcass.yield_mask == 0:
			continue
		paths.append(_path_of(carcass))
		masks.append(carcass.yield_mask)
		if paths.size() >= SNAPSHOT_MAX_CARCASSES:
			break
	if paths.is_empty():
		return
	apply_carcass_snapshot.rpc_id(peer, paths, masks)


# --- 클라이언트 → 호스트 (의도만) ---------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func request_butcher_start(carcass_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_butcher_start", sender, carcass_path.length(), _now_seconds):
		return
	if not RpcGuard.is_safe_relative_path(carcass_path, CARCASS_PATH_MAX_LENGTH):
		push_warning("NetButcher: request_butcher_start 스키마 위반 — 폐기 sender=%d" % sender)
		return
	_host_hold_start(_session.get_player_id_for_peer(sender), carcass_path)


@rpc("any_peer", "call_remote", "reliable")
func request_butcher_cancel(carcass_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_butcher_cancel", sender, carcass_path.length(), _now_seconds):
		return
	if not RpcGuard.is_safe_relative_path(carcass_path, CARCASS_PATH_MAX_LENGTH):
		return
	_hold_sessions.erase(_session_key(_session.get_player_id_for_peer(sender), carcass_path))


@rpc("any_peer", "call_remote", "reliable")
func request_butcher_commit(carcass_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_butcher_commit", sender, carcass_path.length(), _now_seconds):
		return
	if not RpcGuard.is_safe_relative_path(carcass_path, CARCASS_PATH_MAX_LENGTH):
		push_warning("NetButcher: request_butcher_commit 스키마 위반 — 폐기 sender=%d" % sender)
		return
	_host_stage_commit(_session.get_player_id_for_peer(sender), carcass_path)


@rpc("any_peer", "call_remote", "reliable")
func request_drag_toggle(carcass_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_drag_toggle", sender, carcass_path.length(), _now_seconds):
		return
	if not RpcGuard.is_safe_relative_path(carcass_path, CARCASS_PATH_MAX_LENGTH):
		return
	_host_drag_toggle(_session.get_player_id_for_peer(sender), carcass_path)


# --- 호스트 권위 판정 ---------------------------------------------------------

func _host_hold_start(player_id: StringName, carcass_path: String) -> void:
	var carcass: Carcass = _carcass_at(carcass_path)
	var avatar: Player = _avatar_of(player_id)
	if carcass == null or avatar == null or carcass.is_fully_butchered():
		return
	# 도구 없는 홀드는 시작조차 열지 않는다 — 맨손 커밋의 진입점을 막는다.
	if carcass.best_tool_of(avatar) == &"":
		return
	_hold_sessions[_session_key(player_id, carcass_path)] = { start_ticks = _ticks }


func _host_stage_commit(player_id: StringName, carcass_path: String) -> void:
	var key: String = _session_key(player_id, carcass_path)
	var session: Dictionary = _hold_sessions.get(key, {})
	if session.is_empty():
		return  # 세션 없는 커밋 — 변조이거나 이미 취소·확정된 경합.
	var carcass: Carcass = _carcass_at(carcass_path)
	var avatar: Player = _avatar_of(player_id)
	if carcass == null or avatar == null or carcass.is_fully_butchered():
		_hold_sessions.erase(key)
		return

	# 거리는 호스트 월드 기준으로 본다 (설계서 7.4: 클라이언트 주장 금지).
	var distance: float = avatar.global_position.distance_to(carcass.global_position)
	if distance > BUTCHER_MAX_DISTANCE_PX:
		push_warning("NetButcher: 사거리 밖 해체 주장 거부 dist=%.0f" % distance)
		_hold_sessions.erase(key)
		return

	# 홀드 시간은 호스트 시계로 검증한다 — 즉시 커밋 변조 차단 (설계서 7.4).
	var required: float = carcass.stage_seconds_for(avatar)
	if not is_finite(required):
		_hold_sessions.erase(key)
		return  # 도구가 사라졌다.
	var elapsed: float = float(_ticks - int(session.start_ticks)) / float(Engine.physics_ticks_per_second)
	if elapsed < required - BUTCHER_HOLD_SLACK_SECONDS:
		push_warning("NetButcher: 홀드 미달 해체 커밋 거부 (%.2fs < %.2fs) — 변조 의심" % [elapsed, required])
		return  # 세션은 남긴다 — 정직한 클라이언트가 더 홀드해서 완료할 수 있다.

	var stage: int = carcass.next_stage()
	if not carcass.apply_stage(avatar):
		return  # 만석 등으로 지급 실패 — bit 도 세션도 소모하지 않는다.
	_hold_sessions.erase(key)
	if multiplayer.get_peers().size() > 0:
		confirm_butcher_stage.rpc(carcass_path, String(player_id), stage, carcass.yield_mask)


func _host_drag_toggle(player_id: StringName, carcass_path: String) -> void:
	var carcass := _carcass_at(carcass_path)
	var avatar := _avatar_of(player_id)
	if carcass == null or avatar == null:
		return
	if not carcass.toggle_drag_authoritative(avatar):
		return
	replicate_drag_state(carcass, carcass.dragged_by)


# --- 호스트 → 클라이언트 (확정 복제) ------------------------------------------

## 산출 아이템·수량은 보내지 않는다 — 양쪽이 같은 CarcassProfile 을 로드하므로
## 구간 번호만으로 복제본이 같은 결론에 도달한다 (NetCrafting 이 recipe_id 만 쓰는 것과 같다).
@rpc("authority", "call_remote", "reliable")
func confirm_butcher_stage(carcass_path: String, player_id: String, stage: int, mask: int) -> void:
	if not _guard.check(&"confirm_butcher_stage", multiplayer.get_remote_sender_id(),
			carcass_path.length() + player_id.length() + 16, _now_seconds):
		return
	if not RpcGuard.is_safe_relative_path(carcass_path, CARCASS_PATH_MAX_LENGTH) \
			or player_id.is_empty() or player_id.length() > PLAYER_ID_MAX_LENGTH \
			or stage < 0 or mask <= 0:
		push_warning("NetButcher: confirm_butcher_stage 스키마 위반 — 폐기")
		return
	var carcass: Carcass = _carcass_at(carcass_path)
	if carcass == null or stage >= carcass.profile.stage_count:
		return
	carcass.apply_replicated_stage(stage, mask, _avatar_of(StringName(player_id)))


@rpc("authority", "call_remote", "reliable")
func confirm_drag_state(carcass_path: String, player_id: String, position_value: Vector2) -> void:
	if not _guard.check(&"confirm_drag_state", multiplayer.get_remote_sender_id(),
			carcass_path.length() + player_id.length() + 24, _now_seconds):
		return
	if not RpcGuard.is_safe_relative_path(carcass_path, CARCASS_PATH_MAX_LENGTH) \
			or player_id.length() > PLAYER_ID_MAX_LENGTH:
		return
	var carcass := _carcass_at(carcass_path)
	if carcass != null:
		carcass.apply_replicated_drag(
			_avatar_of(StringName(player_id)) if not player_id.is_empty() else null,
			position_value)


@rpc("authority", "call_remote", "unreliable")
func confirm_drag_position(carcass_path: String, position_value: Vector2) -> void:
	if not _guard.check(&"confirm_drag_position", multiplayer.get_remote_sender_id(),
			carcass_path.length() + 16, _now_seconds):
		return
	if not RpcGuard.is_safe_relative_path(carcass_path, CARCASS_PATH_MAX_LENGTH):
		return
	var carcass := _carcass_at(carcass_path)
	if carcass != null and carcass.dragged_by != null:
		carcass.global_position = position_value


@rpc("authority", "call_remote", "reliable")
func apply_carcass_snapshot(paths: PackedStringArray, masks: PackedInt32Array) -> void:
	if not _guard.check(&"apply_carcass_snapshot", multiplayer.get_remote_sender_id(),
			paths.size() * 96 + 32, _now_seconds):
		return
	if paths.size() != masks.size() or paths.size() > SNAPSHOT_MAX_CARCASSES:
		push_warning("NetButcher: apply_carcass_snapshot 스키마 위반 — 폐기")
		return
	for index: int in range(paths.size()):
		if not RpcGuard.is_safe_relative_path(paths[index], CARCASS_PATH_MAX_LENGTH) or masks[index] < 0:
			push_warning("NetButcher: apply_carcass_snapshot 항목 스키마 위반 — 폐기")
			return
	for index: int in range(paths.size()):
		var carcass: Carcass = _carcass_at(paths[index])
		if carcass != null:
			# 스냅샷은 산출을 지급하지 않는다 — 인벤토리는 NetResync 가 소유한다.
			carcass.apply_replicated_mask(masks[index])


# --- 조회 --------------------------------------------------------------------

func _session_key(player_id: StringName, carcass_path: String) -> String:
	return "%s|%s" % [player_id, carcass_path]


func _path_of(carcass: Carcass) -> String:
	return String(_world_root.get_path_to(carcass))


func _carcass_at(carcass_path: String) -> Carcass:
	return _world_root.get_node_or_null(NodePath(carcass_path)) as Carcass


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

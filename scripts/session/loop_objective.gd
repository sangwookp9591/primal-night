class_name LoopObjective
extends Node2D

## 회색 상자 감지 루프의 세션 판정 (계획서 W3-T2, 설계서 4.x).
## 루프: 위험에 노출된다(출혈 → 피 냄새) → 소리·바람으로 랩터를 읽고 피한다 →
## 이 노드 위치(지정 지점)에 도달한다. 노출 없이 지점만 밟는 것은 이 루프가 아니므로
## 성공으로 치지 않는다 — 그렇게 하면 '걸어가기 테스트'가 되고 감지 루프를 검증하지 못한다.
##
## 판정과 시간의 권위는 호스트다. 클라이언트에는 "도달했다"를 주장할 RPC 가 없다:
## 호스트가 자기 월드의 아바타 좌표를 직접 재고, 결과를 신뢰 전송으로 복제할 뿐이다
## (NetPickup/NetSurvival/NetResync 와 같은 골격).

enum Outcome { PENDING, SUCCEEDED, FAILED }

signal outcome_changed(outcome: Outcome)

const SNAPSHOT_MAX_PER_SECOND: int = 10
const SNAPSHOT_PAYLOAD_BYTES: int = 64
## 도달 판정 주기 (틱). 10Hz 면 도달 판정에 충분하다 — 매 프레임 전체 아바타
## 순회는 금지다 (성능문서 6.1).
const CHECK_INTERVAL_TICKS: int = 6

## 지정 지점 반경 (px). 회색 상자라 시각 표식이 없으므로 넉넉히 잡는다.
@export var extraction_radius: float = 96.0
@export var clock_path: NodePath = ^"../SessionClock"
@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"

var outcome: Outcome = Outcome.PENDING
## 세션 단위 플래그다 (2인 협동이므로 누가 노출됐든 그 판이 위험해진다).
var risk_exposed: bool = false

var _clock: SessionClock
var _session: SessionService
var _host_player: Player
var _container: Node2D
var _guard: RpcGuard
var _now_seconds: float = 0.0


func _ready() -> void:
	_clock = get_node(clock_path)
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_clock.phase_expired.connect(_on_phase_expired)
	if has_node("/root/EventBus"):
		var event_bus: Node = get_node("/root/EventBus")
		event_bus.bleeding_started.connect(_on_bleeding_started)
		event_bus.item_picked_up.connect(_on_item_picked_up)
		event_bus.smell_emitted.connect(_on_smell_emitted)
	_guard = RpcGuard.new()
	_guard.register_rule(&"apply_session_snapshot", true, SNAPSHOT_MAX_PER_SECOND, SNAPSHOT_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	# 참가·재접속한 피어는 세션이 이미 얼마나 흘렀는지, 판이 이미 끝났는지 모른다.
	_session.player_joined.connect(_send_snapshot_to)
	_session.player_reconnected.connect(_send_snapshot_to)


func _physics_process(delta: float) -> void:
	_now_seconds += delta
	if not multiplayer.is_server() or outcome != Outcome.PENDING:
		return
	if Engine.get_physics_frames() % CHECK_INTERVAL_TICKS != 0:
		return
	if risk_exposed and _anyone_at_extraction():
		_settle(Outcome.SUCCEEDED)


## 위험 노출 기록 (호스트 권위). 지금은 출혈뿐이지만, W3-T4 의 고기·미끼 같은
## 냄새 원천도 여기로 들어온다 — 랩터를 부르는 상태가 곧 노출이다.
func mark_risk_exposed() -> void:
	if not multiplayer.is_server() or risk_exposed:
		return
	risk_exposed = true


func _on_bleeding_started(target: Node) -> void:
	if target is Player:
		mark_risk_exposed()


func _on_item_picked_up(item_id: StringName, by: Node) -> void:
	if not by is Player:
		return
	var item: ItemData = get_node("/root/GameData").get_item(item_id)
	if item != null and item.is_smell_source():
		mark_risk_exposed()


func _on_smell_emitted(_position: Vector2, strength: float, kind: StringName) -> void:
	if strength > 0.0 and kind != &"blood":
		mark_risk_exposed()


func _on_phase_expired() -> void:
	if not multiplayer.is_server() or outcome != Outcome.PENDING:
		return
	_settle(Outcome.FAILED)


func _anyone_at_extraction() -> bool:
	if _host_player.global_position.distance_to(global_position) <= extraction_radius:
		return true
	for avatar: Node in _container.get_children():
		if avatar is Player and (avatar as Player).global_position.distance_to(global_position) <= extraction_radius:
			return true
	return false


func _settle(result: Outcome) -> void:
	outcome = result
	_clock.stop()
	outcome_changed.emit(outcome)
	apply_session_snapshot.rpc(_clock.remaining_seconds, _clock.running, int(outcome), risk_exposed)


func _send_snapshot_to(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var peer: int = _session.get_peer_for_player(player_id)
	if peer <= 0 or peer == RpcGuard.HOST_PEER_ID:
		return
	apply_session_snapshot.rpc_id(peer, _clock.remaining_seconds, _clock.running,
		int(outcome), risk_exposed)


## 호스트 → 피어: 세션 상태 스냅샷 (남은 시간·진행 여부·판정·노출).
## 결과 확정 시 브로드캐스트, 참가·재접속 시 그 피어에게만 보낸다.
@rpc("authority", "call_remote", "reliable")
func apply_session_snapshot(remaining: float, running: bool, outcome_value: int, exposed: bool) -> void:
	if not _guard.check(&"apply_session_snapshot", multiplayer.get_remote_sender_id(),
			SNAPSHOT_PAYLOAD_BYTES, _now_seconds):
		return
	if not is_finite(remaining) or outcome_value < 0 or outcome_value > int(Outcome.FAILED):
		push_warning("LoopObjective: apply_session_snapshot 스키마 위반 — 폐기")
		return
	_clock.apply_replicated(remaining, running)
	risk_exposed = exposed
	var replicated: Outcome = outcome_value as Outcome
	if outcome != replicated:
		outcome = replicated
		outcome_changed.emit(outcome)

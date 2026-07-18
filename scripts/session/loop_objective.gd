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

enum Outcome { PENDING, STABLE_ESCAPE, FORCED_ESCAPE, REMAIN, FAILED }

signal outcome_changed(outcome: Outcome)

const SNAPSHOT_MAX_PER_SECOND: int = 10
const SNAPSHOT_PAYLOAD_BYTES: int = 64
## 랩터를 부르는 냄새 종류 (양성 지정). 새 냄새 kind 는 여기 넣어야만 노출로 친다 —
## "blood 가 아니면 전부 위험" 식 부정 필터는 연기·조리 냄새가 생기는 순간 어긋난다.
## (blood 는 bleeding_started 전용 경로가 따로 있다.)
const LURE_SMELL_KINDS: Array[StringName] = [&"raw_meat", &"bait"]
## 도달 판정 주기 (틱). 10Hz 면 도달 판정에 충분하다 — 매 프레임 전체 아바타
## 순회는 금지다 (성능문서 6.1).
const CHECK_INTERVAL_TICKS: int = 6
const ACTIVE_LURE_WINDOW_SECONDS: float = 1.5
const OUTCOME_TEXTS: Dictionary = {
	Outcome.PENDING: "",
	Outcome.STABLE_ESCAPE: "피를 멎게 하고 불을 지킨 끝에, 무사히 골짜기를 빠져나왔다.",
	Outcome.FORCED_ESCAPE: "위험의 흔적을 떨치지 못한 채, 대가를 안고 골짜기를 빠져나왔다.",
	Outcome.REMAIN: "밤이 다시 닫혔고, 살아남은 이들은 다음 순환에 남았다.",
	Outcome.FAILED: "살아 돌아갈 이가 없어, 이번 순환은 여기서 끊겼다.",
}

## 지정 지점 반경 (px). 회색 상자라 시각 표식이 없으므로 넉넉히 잡는다.
@export var extraction_radius: float = 96.0
@export var clock_path: NodePath = ^"../SessionClock"
@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"

var outcome: Outcome = Outcome.PENDING
## 세션 단위 플래그다 (2인 협동이므로 누가 노출됐든 그 판이 위험해진다).
var risk_exposed: bool = false
var bleeding_treated: bool = false
var fire_maintained: bool = false
var _last_lure_smell_seconds: float = -INF

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
	_clock.session_expired.connect(_on_session_expired)
	if has_node("/root/EventBus"):
		var event_bus: Node = get_node("/root/EventBus")
		event_bus.bleeding_started.connect(_on_bleeding_started)
		event_bus.bleeding_stopped.connect(_on_bleeding_stopped)
		event_bus.item_picked_up.connect(_on_item_picked_up)
		event_bus.smell_emitted.connect(_on_smell_emitted)
		event_bus.campfire_lit.connect(_on_campfire_lit)
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
		_settle(_escape_outcome())


## 위험 노출 기록 (호스트 권위). 지금은 출혈뿐이지만, W3-T4 의 고기·미끼 같은
## 냄새 원천도 여기로 들어온다 — 랩터를 부르는 상태가 곧 노출이다.
func mark_risk_exposed() -> void:
	if not multiplayer.is_server() or risk_exposed:
		return
	risk_exposed = true


func _on_bleeding_started(target: Node) -> void:
	if target is Player:
		mark_risk_exposed()


func _on_bleeding_stopped(target: Node) -> void:
	if multiplayer.is_server() and target is Player and risk_exposed:
		bleeding_treated = true


func _on_campfire_lit(_campfire: Node, _position: Vector2, _radius: float) -> void:
	if multiplayer.is_server():
		fire_maintained = true


func _on_item_picked_up(item_id: StringName, by: Node) -> void:
	if not by is Player:
		return
	var item: ItemData = get_node("/root/GameData").get_item(item_id)
	if item != null and item.is_smell_source():
		mark_risk_exposed()


func _on_smell_emitted(_position: Vector2, strength: float, kind: StringName) -> void:
	if strength > 0.0 and kind in LURE_SMELL_KINDS:
		_last_lure_smell_seconds = _now_seconds
		mark_risk_exposed()


func _on_session_expired() -> void:
	if not multiplayer.is_server() or outcome != Outcome.PENDING:
		return
	_settle(Outcome.REMAIN if _anyone_alive() else Outcome.FAILED)


func narrative_text() -> String:
	return OUTCOME_TEXTS.get(outcome, "")


func _escape_outcome() -> Outcome:
	if _has_active_bleeding() or _has_active_lure_smell():
		return Outcome.FORCED_ESCAPE
	if bleeding_treated and fire_maintained:
		return Outcome.STABLE_ESCAPE
	return Outcome.FORCED_ESCAPE


func _has_active_lure_smell() -> bool:
	return _now_seconds - _last_lure_smell_seconds <= ACTIVE_LURE_WINDOW_SECONDS


func _has_active_bleeding() -> bool:
	if _host_player.health.is_bleeding:
		return true
	for index: int in range(_container.get_child_count()):
		var avatar: Player = _container.get_child(index) as Player
		if avatar != null and avatar.health.is_bleeding:
			return true
	return false


func _anyone_alive() -> bool:
	if _host_player.health.is_alive():
		return true
	for index: int in range(_container.get_child_count()):
		var avatar: Player = _container.get_child(index) as Player
		if avatar != null and avatar.health.is_alive():
			return true
	return false


## 10Hz 판정 — get_children() 배열 할당 없이 인덱스로 돌고, sqrt 없이 제곱 비교한다.
func _anyone_at_extraction() -> bool:
	var radius_squared: float = extraction_radius * extraction_radius
	if _host_player.global_position.distance_squared_to(global_position) <= radius_squared:
		return true
	for index: int in range(_container.get_child_count()):
		var avatar: Player = _container.get_child(index) as Player
		if avatar != null and avatar.global_position.distance_squared_to(global_position) <= radius_squared:
			return true
	return false


func _settle(result: Outcome) -> void:
	outcome = result
	_clock.stop()
	outcome_changed.emit(outcome)
	apply_session_snapshot.rpc(_clock.current_day, _clock.time_of_day_seconds,
		_clock.running, int(outcome), risk_exposed, bleeding_treated, fire_maintained)


func _send_snapshot_to(player_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var peer: int = _session.get_peer_for_player(player_id)
	if peer <= 0 or peer == RpcGuard.HOST_PEER_ID:
		return
	apply_session_snapshot.rpc_id(peer, _clock.current_day, _clock.time_of_day_seconds,
		_clock.running, int(outcome), risk_exposed, bleeding_treated, fire_maintained)


## 호스트 → 피어: 세션 상태 스냅샷 (day/time·진행 여부·판정·노출).
## 결과 확정 시 브로드캐스트, 참가·재접속 시 그 피어에게만 보낸다.
@rpc("authority", "call_remote", "reliable")
func apply_session_snapshot(day: int, time_of_day: float, running: bool,
		outcome_value: int, exposed: bool, treated: bool, maintained_fire: bool) -> void:
	if not _guard.check(&"apply_session_snapshot", multiplayer.get_remote_sender_id(),
			SNAPSHOT_PAYLOAD_BYTES, _now_seconds):
		return
	if day < 1 or day > _clock.total_days or not is_finite(time_of_day) \
			or time_of_day < 0.0 or time_of_day > _clock.day_duration_seconds() \
			or outcome_value < 0 or outcome_value > int(Outcome.FAILED):
		push_warning("LoopObjective: apply_session_snapshot 스키마 위반 — 폐기")
		return
	_clock.apply_replicated(day, time_of_day, running)
	risk_exposed = exposed
	bleeding_treated = treated
	fire_maintained = maintained_fire
	var replicated: Outcome = outcome_value as Outcome
	if outcome != replicated:
		outcome = replicated
		outcome_changed.emit(outcome)

class_name LoopObjective
extends Node2D

## 회색 상자 감지 루프의 세션 판정 (계획서 W3-T2/W5-T2, 설계서 4.x).
## 루프: 플레이어가 스스로 위험을 만든다(출혈·날고기 획득·미끼 투척 → 랩터를 부르는 냄새) →
## 소리·바람으로 랩터를 읽고 조사/추격을 관측한 뒤 실제로 피한다 → 이 노드 위치(탈출 지점)에
## 도달한다. 노출 없이, 또는 랩터를 관측·회피하지 않고 지점만 밟는 것은 이 루프가 아니므로
## 성공으로 치지 않는다 — 그렇게 하면 '걸어가기 테스트'가 되고 감지 루프를 검증하지 못한다.
##
## ★ 노출 판정 (W5-T2): 월드 배경 냄새와 플레이어 기원 냄새를 구분한다. 디버그 판 바닥에 놓인
## raw_meat 가 주기적으로 EventBus.smell_emitted 를 쏘아도 그것만으로는 노출이 아니다. 출처가
## 플레이어인 것 — 출혈(bleeding_started), 날고기 획득·휴대(item_picked_up), 호스트가 확정한 미끼
## 투척(NetPickup.bait_thrown) — 만 risk_exposed 로 센다.
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

## HUD "현재 조건" 문자열 (도메인이 소유한다 — HUD 는 하드코딩하지 않고 읽어 그린다, 설계서 5.6).
const CONDITION_EXPOSE: StringName = &"위험에 노출되기"
const CONDITION_OBSERVE: StringName = &"랩터를 끌어들이기"
const CONDITION_EVADE: StringName = &"랩터를 따돌리기"
const CONDITION_EXTRACT: StringName = &"탈출 지점으로"
const CONDITION_SUCCEEDED: StringName = &"탈출 성공"
const CONDITION_FAILED: StringName = &"세션 실패"

## 지정 지점 반경 (px). 회색 상자라 시각 표식이 없으므로 넉넉히 잡는다.
@export var extraction_radius: float = 96.0
## 포획 판정 (W5-T2). 데이터로 두어 W5-T5 수치 조정이 코드 수정 없이 가능하다 (씬 인스펙터).
## 랩터가 이 반경 안에 유예 시간 이상 머물면 세션 실패다. 짧은 근접은 허용한다.
@export var capture_radius: float = 72.0
@export var capture_grace_seconds: float = 2.0
## 보이는 탈출 지점 (설계서 3.2: 예고 없는 실패 금지). _draw 로 반경 링을 그린다.
@export var show_extraction_marker: bool = true
@export var clock_path: NodePath = ^"../SessionClock"
@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
## 관측할 랩터 (단일). ponytail: 무리 AI 는 W7 후보라 지금은 한 경로만 본다.
@export var raptor_path: NodePath = ^"../Raptor"
## 호스트 확정 미끼 투척 신호원.
@export var net_pickup_path: NodePath = ^"../NetPickup"

var outcome: Outcome = Outcome.PENDING
## 세션 단위 플래그다 (2인 협동이므로 누가 노출됐든 그 판이 위험해진다).
var risk_exposed: bool = false

var _clock: SessionClock
var _session: SessionService
var _host_player: Player
var _container: Node2D
var _raptor: Raptor
var _guard: RpcGuard
var _now_seconds: float = 0.0
## 성공 순서 (호스트 전용): 노출 이후 랩터 조사/추격을 관측했는가, 그 뒤 회피(FLEE·관심 상실)를
## 관측했는가. 노출 전 상태 전환은 재사용하지 않는다 — 아래 콜백이 risk_exposed 로 먼저 거른다.
var _engaged_after_exposure: bool = false
var _evaded_after_engage: bool = false
## 포획 누적 시간 (반경 안에 연속으로 머문 시간). 반경 밖으로 나가면 0 으로 초기화한다.
var _capture_elapsed: float = 0.0


func _ready() -> void:
	add_to_group(&"loop_objective")
	_clock = get_node(clock_path)
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_clock.phase_expired.connect(_on_phase_expired)
	if has_node(raptor_path):
		_raptor = get_node(raptor_path) as Raptor
		if _raptor != null:
			_raptor.state_changed.connect(_on_raptor_state_changed)
	if has_node(net_pickup_path):
		var net_pickup: Node = get_node(net_pickup_path)
		if net_pickup != null and net_pickup.has_signal(&"bait_thrown"):
			net_pickup.bait_thrown.connect(_on_bait_thrown)
	if has_node("/root/EventBus"):
		var event_bus: Node = get_node("/root/EventBus")
		event_bus.bleeding_started.connect(_on_bleeding_started)
		event_bus.item_picked_up.connect(_on_item_picked_up)
	_guard = RpcGuard.new()
	_guard.register_rule(&"apply_session_snapshot", true, SNAPSHOT_MAX_PER_SECOND, SNAPSHOT_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	# 참가·재접속한 피어는 세션이 이미 얼마나 흘렀는지, 판이 이미 끝났는지 모른다.
	_session.player_joined.connect(_send_snapshot_to)
	_session.player_reconnected.connect(_send_snapshot_to)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_now_seconds += delta
	if not multiplayer.is_server() or outcome != Outcome.PENDING:
		return
	# 포획: 랩터가 포획 반경 안에 유예 이상 머물면 실패. 매 프레임 거리검사지만
	# 랩터 1 × 아바타 소수라 저비용이다 (제곱 비교, sqrt 없음).
	if _raptor_within_capture():
		_capture_elapsed += delta
		if _capture_elapsed >= capture_grace_seconds:
			_settle(Outcome.FAILED)
			return
	else:
		_capture_elapsed = 0.0
	if Engine.get_physics_frames() % CHECK_INTERVAL_TICKS != 0:
		return
	# 성공은 순서를 요구한다: 플레이어 기원 노출 → 랩터 관측 → 회피 → 탈출 지점.
	if _success_sequence_ready() and _anyone_at_extraction():
		_settle(Outcome.SUCCEEDED)


func _success_sequence_ready() -> bool:
	return risk_exposed and _engaged_after_exposure and _evaded_after_engage


## 위험 노출 기록 (호스트 권위). 플레이어 기원 냄새 원천만 여기로 들어온다 — 출혈, 날고기
## 획득·휴대, 호스트 확정 미끼 투척. 월드 배경 냄새(바닥 raw_meat 주기 발신)는 오지 않는다.
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


## NetPickup 이 성공한 호스트 투척을 직접 알린다 (전역 smell_emitted 를 경유하지 않는다).
func _on_bait_thrown(_by: Player, _position: Vector2) -> void:
	mark_risk_exposed()


## 노출 이후의 랩터 전환만 성공 순서에 반영한다. 노출 전 조사/추격은 재사용하지 않는다.
func _on_raptor_state_changed(_previous_state: int, new_state: int) -> void:
	if not multiplayer.is_server() or outcome != Outcome.PENDING or not risk_exposed:
		return
	if new_state == Raptor.State.INVESTIGATE or new_state == Raptor.State.CHASE:
		_engaged_after_exposure = true
	elif _engaged_after_exposure and (new_state == Raptor.State.FLEE or new_state == Raptor.State.WANDER):
		# 실제 회피: 불 보호로 도주(FLEE)했거나 관심을 잃고 배회로 돌아왔다.
		_evaded_after_engage = true


func _on_phase_expired() -> void:
	if not multiplayer.is_server() or outcome != Outcome.PENDING:
		return
	_settle(Outcome.FAILED)


## 포획: 랩터가 어느 아바타든 포획 반경 안에 있는가. 제곱 비교, 배열 할당 없음.
func _raptor_within_capture() -> bool:
	if _raptor == null or not is_instance_valid(_raptor):
		return false
	var radius_squared: float = capture_radius * capture_radius
	var raptor_position: Vector2 = _raptor.global_position
	if _host_player != null and raptor_position.distance_squared_to(_host_player.global_position) <= radius_squared:
		return true
	for index: int in range(_container.get_child_count()):
		var avatar: Player = _container.get_child(index) as Player
		if avatar != null and raptor_position.distance_squared_to(avatar.global_position) <= radius_squared:
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


## HUD 표시용 (읽기 전용). 현재 세션이 요구하는 다음 조건.
func current_condition() -> StringName:
	if outcome == Outcome.SUCCEEDED:
		return CONDITION_SUCCEEDED
	if outcome == Outcome.FAILED:
		return CONDITION_FAILED
	if not risk_exposed:
		return CONDITION_EXPOSE
	if not _engaged_after_exposure:
		return CONDITION_OBSERVE
	if not _evaded_after_engage:
		return CONDITION_EVADE
	return CONDITION_EXTRACT


## HUD 표시용 (읽기 전용). 남은 phase 초 — 시계는 클라이언트도 로컬로 돌려 화면을 채운다.
func session_remaining_seconds() -> float:
	return _clock.remaining_seconds if _clock != null else 0.0


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


## 보이는 탈출 지점 — 회색 상자 링. 호스트·클라이언트 모두 그린다 (표식은 순수 시각).
func _draw() -> void:
	if not show_extraction_marker:
		return
	var color: Color = Color(0.3, 0.9, 0.5, 0.9)
	draw_arc(Vector2.ZERO, extraction_radius, 0.0, TAU, 48, color, 3.0, true)
	draw_circle(Vector2.ZERO, 6.0, color)

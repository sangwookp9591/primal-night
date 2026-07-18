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
enum RiftSignal { DORMANT, CALM, UNSTABLE }
enum BodySignal { NONE, STEADY_BREATH, GUARDED }

signal outcome_changed(outcome: Outcome)
signal death_cause_changed(text: String)
signal rift_signal_changed(rift_signal: RiftSignal, body_signal: BodySignal)
signal environmental_narration(text: String)

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
const CAUSE_HISTORY_CAPACITY: int = 12
const FINAL_NIGHT_TEXT: String = "균열이 닫혀간다. 남기로 한다면 불을 지켜라."
const OUTCOME_TEXTS: Dictionary = {
	Outcome.PENDING: "",
	Outcome.STABLE_ESCAPE: "피를 멎게 하고 불을 지킨 끝에, 무사히 골짜기를 빠져나왔다. 남긴 위험은 없었다.",
	Outcome.FORCED_ESCAPE: "위험의 흔적을 떨치지 못한 채 골짜기를 빠져나왔다. 급히 떠난 대가로 장비 일부를 남겼다.",
	Outcome.REMAIN: "밤이 다시 닫혔다. 불을 지켜 온 생존자들은 떠나지 않고 다음 순환에 남았다.",
	Outcome.FAILED: "살아 돌아갈 이가 없어, 이번 순환은 여기서 끊겼다.",
}

## 지정 지점 반경 (px). 회색 상자라 시각 표식이 없으므로 넉넉히 잡는다.
@export var extraction_radius: float = 96.0
@export var clock_path: NodePath = ^"../SessionClock"
@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
@export var base_camp_path: NodePath = ^"../SurvivalDemo/CampfireSite"
@export var base_narration_radius: float = 240.0

var outcome: Outcome = Outcome.PENDING
## 세션 단위 플래그다 (2인 협동이므로 누가 노출됐든 그 판이 위험해진다).
var risk_exposed: bool = false
var bleeding_treated: bool = false
var fire_maintained: bool = false
var death_cause_text: String = ""
var cause_history: Array[Dictionary] = []
var rift_signal: RiftSignal = RiftSignal.DORMANT
var body_signal: BodySignal = BodySignal.NONE
var last_environmental_narration: String = ""
var _last_lure_smell_seconds: float = -INF

var _clock: SessionClock
var _session: SessionService
var _host_player: Player
var _container: Node2D
var _guard: RpcGuard
var _now_seconds: float = 0.0
var _final_night_narrated: bool = false
var _narration_label: Label
var _body_signal_line: Line2D


func _ready() -> void:
	_clock = get_node(clock_path)
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_clock.session_expired.connect(_on_session_expired)
	_clock.phase_changed.connect(_on_clock_phase_changed)
	if has_node("/root/EventBus"):
		var event_bus: Node = get_node("/root/EventBus")
		event_bus.bleeding_started.connect(_on_bleeding_started)
		event_bus.bleeding_stopped.connect(_on_bleeding_stopped)
		event_bus.item_picked_up.connect(_on_item_picked_up)
		event_bus.smell_emitted.connect(_on_smell_emitted)
		event_bus.campfire_lit.connect(_on_campfire_lit)
		event_bus.noise_emitted.connect(_on_noise_emitted)
		event_bus.damage_taken.connect(_on_damage_taken)
	_guard = RpcGuard.new()
	_guard.register_rule(&"apply_session_snapshot", true, SNAPSHOT_MAX_PER_SECOND, SNAPSHOT_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	# 참가·재접속한 피어는 세션이 이미 얼마나 흘렀는지, 판이 이미 끝났는지 모른다.
	_session.player_joined.connect(_send_snapshot_to)
	_session.player_reconnected.connect(_send_snapshot_to)
	_build_environment_placeholders()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_now_seconds += delta
	_refresh_extraction_signals()
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
		record_cause_event(&"blood", (target as Player).global_position)


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
		record_cause_event(&"lure", (by as Player).global_position)


func _on_smell_emitted(_position: Vector2, strength: float, kind: StringName) -> void:
	if strength > 0.0 and kind in LURE_SMELL_KINDS:
		_last_lure_smell_seconds = _now_seconds
		mark_risk_exposed()
		record_cause_event(&"lure", _position)


func _on_noise_emitted(position: Vector2, radius: float, source: Node) -> void:
	if multiplayer.is_server() and radius > 0.0 and source is Player:
		record_cause_event(&"noise", position)


func _on_damage_taken(target: Node, _amount: float, _kind: StringName) -> void:
	if not multiplayer.is_server() or target != _host_player or _host_player.health.is_alive():
		return
	death_cause_text = compose_death_cause()
	death_cause_changed.emit(death_cause_text)


func record_cause_event(kind: StringName, position: Vector2 = Vector2.ZERO) -> void:
	if not multiplayer.is_server():
		return
	cause_history.append({kind = kind, position = position, time = _now_seconds})
	while cause_history.size() > CAUSE_HISTORY_CAPACITY:
		cause_history.pop_front()


func latest_cause_kind() -> StringName:
	if cause_history.is_empty():
		return &"sight"
	return cause_history.back().kind as StringName


func compose_death_cause(cause_override: StringName = &"", raptor_state_override: int = -1,
		wind_override: Vector2 = Vector2.INF) -> String:
	var cause: StringName = latest_cause_kind() if cause_override == &"" else cause_override
	var raptor_state: int = _nearest_raptor_state() if raptor_state_override < 0 \
		else raptor_state_override
	var wind: Vector2 = _current_wind_direction() if wind_override == Vector2.INF else wind_override
	var wind_name: String = _wind_name(wind)
	match cause:
		&"blood":
			if not wind_name.is_empty():
				return "멎지 않은 피 냄새가 %s을 타고 랩터의 순찰 구역까지 퍼졌다." % wind_name
			return "멎지 않은 피 냄새가 발밑에 머물러 랩터를 끝내 이곳으로 이끌었다."
		&"noise":
			if raptor_state == Raptor.State.CHASE:
				return "급한 발소리가 랩터의 고개를 돌렸고, 시작된 추격을 떨치지 못했다."
			return "되풀이된 소음이 어둠 속 랩터에게 마지막 위치를 알려 주었다."
		&"lure":
			if not wind_name.is_empty():
				return "버리지 못한 유인 냄새가 %s을 타고 퍼져 랩터의 조사 경로와 겹쳤다." % wind_name
			return "몸에 밴 고기 냄새가 랩터의 조사를 가까이 끌어들였다."
		_:
			if raptor_state == Raptor.State.CHASE:
				return "랩터의 시야에 오래 머문 끝에, 추격을 끊을 엄폐물을 찾지 못했다."
			return "랩터의 순찰선 안으로 들어선 순간, 숨을 곳을 고를 시간이 부족했다."


func _nearest_raptor_state() -> int:
	var best_state: int = Raptor.State.WANDER
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"raptor"):
		var raptor := node as Raptor
		if raptor == null or raptor.multiplayer != multiplayer:
			continue
		var distance: float = raptor.global_position.distance_squared_to(_host_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best_state = raptor.state
	return best_state


func _current_wind_direction() -> Vector2:
	var grid: SmellGrid = SmellGrid.find_in(get_tree())
	return grid.wind_direction if grid != null else Vector2.ZERO


func _wind_name(direction: Vector2) -> String:
	if direction.is_zero_approx():
		return ""
	var names: Array[String] = ["동풍", "남동풍", "남풍", "남서풍", "서풍", "북서풍", "북풍", "북동풍"]
	var sector: int = wrapi(roundi(direction.angle() / (PI / 4.0)), 0, 8)
	return names[sector]


func _on_session_expired() -> void:
	if not multiplayer.is_server() or outcome != Outcome.PENDING:
		return
	_settle(Outcome.REMAIN if _anyone_alive() else Outcome.FAILED)


func narrative_text() -> String:
	var summary: String = OUTCOME_TEXTS.get(outcome, "")
	if outcome == Outcome.FORCED_ESCAPE:
		return "%s 남긴 위험: %s" % [summary, compose_result_cause()]
	if outcome == Outcome.FAILED:
		return "%s %s" % [summary, compose_result_cause()]
	return summary


func compose_result_cause() -> String:
	## 사망 원인과 같은 감각 인과 문장을 결과 화면에도 재사용한다.
	return death_cause_text if not death_cause_text.is_empty() else compose_death_cause()


func expected_rift_signal() -> RiftSignal:
	if not _is_anyone_near_extraction():
		return RiftSignal.DORMANT
	if _escape_outcome() == Outcome.STABLE_ESCAPE and not _has_active_chase():
		return RiftSignal.CALM
	return RiftSignal.UNSTABLE


func expected_body_signal(for_rift_signal: RiftSignal = expected_rift_signal()) -> BodySignal:
	if for_rift_signal == RiftSignal.CALM:
		return BodySignal.STEADY_BREATH
	if for_rift_signal == RiftSignal.UNSTABLE:
		return BodySignal.GUARDED
	return BodySignal.NONE


func should_narrate_final_night(player_position: Vector2, base_position: Vector2) -> bool:
	return _clock.current_day == _clock.total_days \
		and _clock.current_phase == SessionClock.Phase.NIGHT \
		and player_position.distance_squared_to(base_position) \
			<= base_narration_radius * base_narration_radius


func _on_clock_phase_changed(phase: SessionClock.Phase) -> void:
	if phase != SessionClock.Phase.NIGHT or _final_night_narrated:
		return
	var base := get_node_or_null(base_camp_path) as Node2D
	if base == null or not should_narrate_final_night(_host_player.global_position, base.global_position):
		return
	_final_night_narrated = true
	last_environmental_narration = FINAL_NIGHT_TEXT
	_narration_label.global_position = base.global_position + Vector2(0.0, -54.0)
	_narration_label.text = FINAL_NIGHT_TEXT
	_narration_label.visible = true
	environmental_narration.emit(FINAL_NIGHT_TEXT)


func _refresh_extraction_signals() -> void:
	var next_rift: RiftSignal = expected_rift_signal()
	var next_body: BodySignal = expected_body_signal(next_rift)
	if next_rift == rift_signal and next_body == body_signal:
		_animate_placeholders()
		return
	rift_signal = next_rift
	body_signal = next_body
	rift_signal_changed.emit(rift_signal, body_signal)
	queue_redraw()
	_animate_placeholders()


func _animate_placeholders() -> void:
	if _body_signal_line == null:
		return
	if rift_signal == RiftSignal.UNSTABLE:
		queue_redraw()
	_body_signal_line.visible = body_signal != BodySignal.NONE
	if not _body_signal_line.visible:
		return
	var pulse: float = sin(_now_seconds * (2.2 if body_signal == BodySignal.STEADY_BREATH else 8.0))
	_body_signal_line.scale = Vector2.ONE * (1.0 + pulse * (0.035 if body_signal == BodySignal.STEADY_BREATH else 0.08))
	_body_signal_line.default_color = Color(0.68, 0.86, 0.8, 0.72) \
		if body_signal == BodySignal.STEADY_BREATH else Color(0.88, 0.44, 0.35, 0.82)


func _build_environment_placeholders() -> void:
	_narration_label = Label.new()
	_narration_label.name = "FinalNightWorldNarration"
	_narration_label.visible = false
	_narration_label.z_index = 20
	add_child(_narration_label)
	_body_signal_line = Line2D.new()
	_body_signal_line.name = "ExtractionBodySignal"
	_body_signal_line.width = 2.0
	_body_signal_line.points = PackedVector2Array([
		Vector2(-11.0, -24.0), Vector2(0.0, -29.0), Vector2(11.0, -24.0)])
	_host_player.add_child(_body_signal_line)


func _draw() -> void:
	var color := Color(0.28, 0.34, 0.4, 0.35)
	var offset := Vector2.ZERO
	if rift_signal == RiftSignal.CALM:
		color = Color(0.47, 0.82, 0.75, 0.82)
	elif rift_signal == RiftSignal.UNSTABLE:
		color = Color(0.9, 0.3, 0.25, 0.9)
		offset = Vector2(sin(_now_seconds * 19.0), cos(_now_seconds * 23.0)) * 4.0
	draw_arc(offset, 42.0, -2.45, 2.45, 20, color, 5.0)
	draw_line(offset + Vector2(-12.0, -35.0), offset + Vector2(8.0, 34.0), color, 3.0)


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


func _has_active_chase() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"raptor"):
		var raptor := node as Raptor
		if raptor != null and raptor.multiplayer == multiplayer and raptor.state == Raptor.State.CHASE:
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


func _is_anyone_near_extraction() -> bool:
	## 표현은 판정보다 조금 먼저 읽혀야 하므로 접근 반경을 1.75배 넓힌다.
	var signal_radius: float = extraction_radius * 1.75
	var radius_squared: float = signal_radius * signal_radius
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

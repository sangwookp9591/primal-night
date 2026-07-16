class_name SensePlaytestRecorder
extends Node

## 재미 판정용 세션 recorder (계획서 W5-T3, §6.2). 디버그 전용 판(sense_playtest.tscn)에서만
## 배선하며 main.tscn 에는 넣지 않는다 — 이 위치가 곧 "디버그 빌드에서만" 게이트다 (§8).
##
## 소리/냄새 단서, 랩터 상태 전환, 웅크리기·미끼·모닥불 선택, 포획/탈출, 플레이어의 사전 예측
## 표식을 세션 상대 단조 시각으로 메모리에만 쌓는다. 세션 종료(LoopObjective.outcome_changed)
## 시점에 user:// 에 익명 JSON 1개를 딱 한 번 쓴다. ★ 종료 전에는 디스크를 건드리지 않는다.
##
## 예측 판정(계획서 §6.2 부등식):
##   유효: prediction_at < clue_emitted_at <= prediction_at + 5초  (같은 채널 최초 단서 기준)
##   적중: 그 단서 뒤 최초 랩터 전환이 clue_emitted_at < state_changed_at <= clue_emitted_at + 5초
##         이며 predicted_next_state(=INVESTIGATE)와 같을 때만.
##   단서 뒤 입력은 이전 단서 적중으로 소급하지 않는다(미결 표식은 다음 단서를 기다린다).
##
## ★ 순수 집계(on_prediction/on_clue/on_state_change/on_choice/on_outcome)는 명시 timestamp 만
## 받는다 — 실제 플레이에선 신호/입력이 세션 시각으로 이 메서드들을 부른다. 테스트는 직접 부른다.

const SCHEMA_VERSION: int = 1
const PREDICTION_WINDOW_SECONDS: float = 5.0
const GROUP: StringName = &"sense_playtest_recorder"

const CHANNEL_SOUND: StringName = &"sound"
const CHANNEL_SMELL: StringName = &"smell"
const PREDICTED_STATE_NAME: StringName = &"investigate"  # Raptor.STATE_NAMES[INVESTIGATE]

const CHOICE_CROUCH: StringName = &"crouch"
const CHOICE_BAIT: StringName = &"bait"
const CHOICE_CAMPFIRE: StringName = &"campfire"

## HUD 대기 표식용 채널 표시 이름 (도메인이 소유 — HUD 는 읽어 그린다, 설계서 5.6).
const CHANNEL_LABELS: Dictionary = { &"sound": "소리", &"smell": "냄새" }

@export var raptor_path: NodePath = ^"../Raptor"
@export var loop_objective_path: NodePath = ^"../LoopObjective"
@export var net_pickup_path: NodePath = ^"../NetPickup"

var _elapsed: float = 0.0
var _predictions: Array[Dictionary] = []
var _clues: Array[Dictionary] = []
var _transitions: Array[Dictionary] = []
var _choices: Array[Dictionary] = []
var _outcomes: Array[Dictionary] = []
## 채널별 미결 예측(단서 대기). 채널당 1개만 허용한다.
var _pending: Dictionary = {}
## 유효 예측 중 '단서 뒤 최초 랩터 전환'을 기다리는 목록.
var _awaiting: Array[Dictionary] = []
var _next_prediction_id: int = 0
var _wrote: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	if has_node(raptor_path):
		var raptor: Node = get_node(raptor_path)
		if raptor != null and raptor.has_signal(&"state_changed"):
			raptor.state_changed.connect(_on_raptor_state_changed)
	if has_node(loop_objective_path):
		var objective: Node = get_node(loop_objective_path)
		if objective != null and objective.has_signal(&"outcome_changed"):
			objective.outcome_changed.connect(_on_outcome_changed)
	if has_node(net_pickup_path):
		var net_pickup: Node = get_node(net_pickup_path)
		if net_pickup != null and net_pickup.has_signal(&"bait_thrown"):
			net_pickup.bait_thrown.connect(_on_bait_thrown)
	if has_node("/root/EventBus"):
		var event_bus: Node = get_node("/root/EventBus")
		event_bus.noise_emitted.connect(_on_noise_emitted)
		event_bus.smell_emitted.connect(_on_smell_emitted)
		event_bus.campfire_lit.connect(_on_campfire_lit)
	set_process(true)


## 세션 상대 단조 시각을 굴리고, 예측/웅크리기 입력을 폴링한다 (디버그 recorder라 입력 폴링 허용).
func _process(delta: float) -> void:
	_elapsed += delta
	if Input.is_action_just_pressed(&"predict_sound"):
		on_prediction(CHANNEL_SOUND, _elapsed)
	if Input.is_action_just_pressed(&"predict_smell"):
		on_prediction(CHANNEL_SMELL, _elapsed)
	if Input.is_action_just_pressed(&"crouch"):
		on_choice(CHOICE_CROUCH, _elapsed)


func now() -> float:
	return _elapsed


# ── 순수 집계 (명시 timestamp) ────────────────────────────────────────────────

## 사전 예측 표식. 채널당 미결 1개만 — 이미 대기 중이면 무시한다.
func on_prediction(channel: StringName, at: float) -> void:
	if channel != CHANNEL_SOUND and channel != CHANNEL_SMELL:
		return
	if _pending.has(channel):
		return
	var record: Dictionary = {
		prediction_id = _next_prediction_id,
		channel = channel,
		predicted_next_state = PREDICTED_STATE_NAME,
		prediction_at = at,
		clue_emitted_at = -1.0,
		state_changed_at = -1.0,
		valid = false,
		hit = false,
		invalid_reason = "",
	}
	_next_prediction_id += 1
	# 같은 Dictionary 참조를 _pending·_awaiting·_predictions 가 공유한다 (이후 제자리 갱신).
	_pending[channel] = record
	_predictions.append(record)


## 단서(소리/냄새). 같은 채널 미결 예측이 있으면 유효성을 판정하고 소비한다.
func on_clue(channel: StringName, at: float) -> void:
	_clues.append({ channel = channel, at = at })
	if not _pending.has(channel):
		return
	var record: Dictionary = _pending[channel]
	_pending.erase(channel)
	record.clue_emitted_at = at
	if at > record.prediction_at and at <= record.prediction_at + PREDICTION_WINDOW_SECONDS:
		record.valid = true
		_awaiting.append(record)
	else:
		record.invalid_reason = "clue_out_of_window"


## 랩터 상태 전환. 대기 중인 유효 예측에게 이것이 '단서 뒤 최초 전환'이다.
func on_state_change(new_state: int, at: float) -> void:
	var state_name: StringName = Raptor.STATE_NAMES[new_state]
	_transitions.append({ to = state_name, at = at })
	if _awaiting.is_empty():
		return
	for record: Dictionary in _awaiting:
		record.state_changed_at = at
		record.hit = at > record.clue_emitted_at \
			and at <= record.clue_emitted_at + PREDICTION_WINDOW_SECONDS \
			and state_name == record.predicted_next_state
	_awaiting.clear()


## 회피 선택 (웅크리기·미끼·모닥불).
func on_choice(kind: StringName, at: float) -> void:
	_choices.append({ kind = kind, at = at })


## 세션 판정 (탈출 성공/포획·시간 만료 실패).
func on_outcome(outcome: int, at: float) -> void:
	_outcomes.append({ outcome = outcome, at = at })


# ── 신호/입력 어댑터 (세션 시각으로 순수 집계를 부른다) ────────────────────────

func _on_noise_emitted(_position: Vector2, _radius: float, _source: Node) -> void:
	on_clue(CHANNEL_SOUND, _elapsed)

func _on_smell_emitted(_position: Vector2, _strength: float, _kind: StringName) -> void:
	on_clue(CHANNEL_SMELL, _elapsed)

func _on_raptor_state_changed(_previous_state: int, new_state: int) -> void:
	on_state_change(new_state, _elapsed)

func _on_bait_thrown(_by: Node, _position: Vector2) -> void:
	on_choice(CHOICE_BAIT, _elapsed)

func _on_campfire_lit(_campfire: Node, _position: Vector2, _radius: float) -> void:
	on_choice(CHOICE_CAMPFIRE, _elapsed)

## 세션 종료 = 판정 확정. 여기서 딱 한 번 디스크에 쓴다.
func _on_outcome_changed(outcome: int) -> void:
	on_outcome(outcome, _elapsed)
	flush()


# ── 집계·조회 (읽기 전용) ─────────────────────────────────────────────────────

func pending_summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for channel: StringName in [CHANNEL_SOUND, CHANNEL_SMELL]:
		if _pending.has(channel):
			parts.append(CHANNEL_LABELS[channel])
	return " ".join(parts)

func is_pending(channel: StringName) -> bool:
	return _pending.has(channel)

## §6.2 예측 표본: valid=true 레코드 수 (채널 지정 시 그 채널만).
func valid_count(channel: StringName = &"") -> int:
	var total: int = 0
	for record: Dictionary in _predictions:
		if record.valid and (channel == &"" or record.channel == channel):
			total += 1
	return total

## §6.2 예측 정확도: hit / valid (채널 지정 가능). 유효 표본이 없으면 0.
func hit_count(channel: StringName = &"") -> int:
	var total: int = 0
	for record: Dictionary in _predictions:
		if record.valid and record.hit and (channel == &"" or record.channel == channel):
			total += 1
	return total

func prediction_accuracy(channel: StringName = &"") -> float:
	var valid: int = valid_count(channel)
	return float(hit_count(channel)) / float(valid) if valid > 0 else 0.0

## 공정 경고: 마지막 CHASE 진입부터 포획(FAILED)까지 (초). 포획·CHASE 없으면 -1.
func warning_time_before_capture() -> float:
	var capture_at: float = -1.0
	for entry: Dictionary in _outcomes:
		if entry.outcome == LoopObjective.Outcome.FAILED:
			capture_at = entry.at
			break
	if capture_at < 0.0:
		return -1.0
	var chase_at: float = -1.0
	for transition: Dictionary in _transitions:
		if transition.to == &"chase" and transition.at <= capture_at:
			chase_at = transition.at
	if chase_at < 0.0:
		return -1.0
	return capture_at - chase_at

func has_written() -> bool:
	return _wrote


# ── 출력 (익명 JSON) ──────────────────────────────────────────────────────────

func build_report() -> Dictionary:
	return {
		schema_version = SCHEMA_VERSION,
		predictions = _predictions,
		clues = _clues,
		raptor_transitions = _transitions,
		choices = _choices,
		outcomes = _outcomes,
		summary = {
			valid_total = valid_count(),
			valid_sound = valid_count(CHANNEL_SOUND),
			valid_smell = valid_count(CHANNEL_SMELL),
			hit_total = hit_count(),
			hit_sound = hit_count(CHANNEL_SOUND),
			hit_smell = hit_count(CHANNEL_SMELL),
		},
	}

## 세션 종료 시 기본 경로에 딱 한 번 쓴다. 익명이라 플레이어 id·이름을 담지 않는다.
func flush() -> void:
	if _wrote:
		return
	write_session(default_path())

func default_path() -> String:
	return "user://sense_playtest_%d.json" % Time.get_ticks_msec()

func write_session(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(build_report(), "\t"))
	file.close()
	_wrote = true
	return OK

class_name SessionClock
extends Node

## 호스트 권위 3일 시계. 하루는 낮 7분 + 황혼 1분 + 밤 2분이다.
## 클라이언트는 표시용으로만 예측하며 LoopObjective의 authority RPC가 권위 값을 덮어쓴다.
## ponytail: 참가·재접속·결과 때만 동기화한다. 표류가 보이면 저주기 스냅샷을 추가한다.

enum Phase { DAYLIGHT, DUSK, NIGHT }

signal time_changed(day: int, time_of_day_seconds: float, phase: Phase)
signal day_changed(day: int)
signal phase_changed(phase: Phase)
signal session_expired

@export var daylight_duration_seconds: float = 420.0
@export var dusk_duration_seconds: float = 60.0
@export var night_duration_seconds: float = 120.0
@export var total_days: int = 3
@export var speed_multiplier: float = 1.0

var current_day: int = 1
var time_of_day_seconds: float = 0.0
var current_phase: Phase = Phase.DAYLIGHT
var remaining_seconds: float = 0.0
var running: bool = false


func _ready() -> void:
	reset()
	start()


func _physics_process(delta: float) -> void:
	# 클라이언트도 표시용으로 예측하지만 판정에는 쓰이지 않고 권위 스냅샷이 덮어쓴다.
	advance(delta)


func reset() -> void:
	current_day = 1
	time_of_day_seconds = 0.0
	current_phase = Phase.DAYLIGHT
	remaining_seconds = session_duration_seconds()
	running = false


func start() -> void:
	if not is_expired():
		running = true


func stop() -> void:
	running = false


func day_duration_seconds() -> float:
	return daylight_duration_seconds + dusk_duration_seconds + night_duration_seconds


func session_duration_seconds() -> float:
	return day_duration_seconds() * float(total_days)


## 큰 delta와 속도 배율에서도 모든 phase/day 경계를 순서대로 통과한다.
func advance(delta: float) -> void:
	if not running or delta <= 0.0 or not is_finite(delta) \
			or speed_multiplier <= 0.0 or not is_finite(speed_multiplier):
		return
	var amount: float = delta * speed_multiplier
	while amount > 0.0 and running:
		var boundary: float = _next_boundary_seconds()
		var moved: float = minf(amount, boundary - time_of_day_seconds)
		time_of_day_seconds += moved
		remaining_seconds = maxf(remaining_seconds - moved, 0.0)
		amount -= moved
		if time_of_day_seconds >= boundary - 0.000001:
			_cross_boundary()
	time_changed.emit(current_day, time_of_day_seconds, current_phase)


func is_expired() -> bool:
	return remaining_seconds <= 0.0


func phase_label() -> String:
	match current_phase:
		Phase.DUSK:
			return "황혼"
		Phase.NIGHT:
			return "밤"
		_:
			return "낮"


## LoopObjective의 authority RPC가 호출하는 클라이언트 스냅샷 적용 경계.
func apply_replicated(day: int, time_of_day: float, is_running: bool) -> void:
	var previous_day: int = current_day
	var previous_phase: Phase = current_phase
	current_day = clampi(day, 1, total_days)
	time_of_day_seconds = clampf(time_of_day, 0.0, day_duration_seconds())
	current_phase = _phase_at(time_of_day_seconds)
	remaining_seconds = maxf(session_duration_seconds() \
		- float(current_day - 1) * day_duration_seconds() - time_of_day_seconds, 0.0)
	running = is_running and not is_expired()
	if current_day != previous_day:
		day_changed.emit(current_day)
	if current_phase != previous_phase:
		phase_changed.emit(current_phase)
	time_changed.emit(current_day, time_of_day_seconds, current_phase)


func _next_boundary_seconds() -> float:
	match current_phase:
		Phase.DAYLIGHT:
			return daylight_duration_seconds
		Phase.DUSK:
			return daylight_duration_seconds + dusk_duration_seconds
		_:
			return day_duration_seconds()


func _cross_boundary() -> void:
	match current_phase:
		Phase.DAYLIGHT:
			current_phase = Phase.DUSK
			phase_changed.emit(current_phase)
		Phase.DUSK:
			current_phase = Phase.NIGHT
			phase_changed.emit(current_phase)
		Phase.NIGHT:
			if current_day < total_days:
				current_day += 1
				time_of_day_seconds = 0.0
				day_changed.emit(current_day)
				current_phase = Phase.DAYLIGHT
				phase_changed.emit(current_phase)
			else:
				time_of_day_seconds = day_duration_seconds()
				remaining_seconds = 0.0
				running = false
				session_expired.emit()


func _phase_at(time_of_day: float) -> Phase:
	if time_of_day < daylight_duration_seconds:
		return Phase.DAYLIGHT
	if time_of_day < daylight_duration_seconds + dusk_duration_seconds:
		return Phase.DUSK
	return Phase.NIGHT

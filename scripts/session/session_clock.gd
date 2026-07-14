class_name SessionClock
extends Node

## 세션의 초 단위 phase_time (설계서 4.x, 계획서 W3-T2).
## 7일 구조는 아직 만들지 않는다 — 한 phase 의 남은 초만 센다.
##
## 시간의 권위는 호스트다. 클라이언트도 같은 카운트다운을 로컬로 돌리지만(그래야
## 초당 RPC 없이 남은 시간을 보여줄 수 있다), 그 값은 아무것도 판정하지 않는다:
## 세션 판정(LoopObjective)은 호스트 시계만 보고, 클라이언트 시계는 참가·재접속·
## 결과 스냅샷이 도착할 때마다 호스트 값으로 덮인다.
## ponytail: 초당 시간 동기 RPC 는 없다. 표류가 눈에 띄면 그때 저주기 동기를 얹는다.

signal phase_expired

## 10~15분 루프 (계획서 W3-T2). 기본 12분.
@export var phase_duration_seconds: float = 720.0

var remaining_seconds: float = 0.0
var running: bool = false


func _ready() -> void:
	reset()
	start()


func _physics_process(delta: float) -> void:
	advance(delta)


func reset() -> void:
	remaining_seconds = phase_duration_seconds
	running = false


func start() -> void:
	running = true


func stop() -> void:
	running = false


## 시간을 주입해 진행한다 — 테스트 결정성 (RpcGuard.check 의 now_seconds 관례).
func advance(delta: float) -> void:
	if not running or remaining_seconds <= 0.0:
		return
	remaining_seconds = maxf(remaining_seconds - delta, 0.0)
	if remaining_seconds <= 0.0:
		running = false
		phase_expired.emit()


func is_expired() -> bool:
	return remaining_seconds <= 0.0


## 호스트 스냅샷으로 맞춘다. 클램프는 방어선이다 — 스냅샷은 권위 경로지만
## 시계가 phase 상한 밖으로 나가면 그 뒤 모든 판정이 무의미해진다.
func apply_replicated(remaining: float, is_running: bool) -> void:
	remaining_seconds = clampf(remaining, 0.0, phase_duration_seconds)
	running = is_running

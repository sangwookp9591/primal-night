class_name Campfire
extends Node2D

## 모닥불. 연료가 떨어지면 꺼진다 (단순 타이머).
## light_radius 는 T4 의 랩터가 회피 판단에 쓴다.
## 타는 동안에만 _process 를 켠다 (성능문서 6.1).

const DEFAULT_CONFIG: CampfireConfig = preload("res://data/props/campfire_config.tres")

@export var config: CampfireConfig = DEFAULT_CONFIG

var is_lit: bool = false
var fuel_remaining: float = 0.0

var _event_bus: Node = null

func _ready() -> void:
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	set_process(false)

func _process(delta: float) -> void:
	if not is_lit:
		return

	fuel_remaining = maxf(fuel_remaining - delta, 0.0)
	if fuel_remaining <= 0.0:
		extinguish()

func light() -> void:
	if is_lit:
		return

	is_lit = true
	fuel_remaining = config.fuel_seconds
	# 연료 소진 타이머는 호스트 소유 (설계서 7.2). 클라이언트 복제본은 타이머를
	# 돌리지 않고 NetCampfire 의 소등 복제만 받는다 (W2-T5).
	set_process(multiplayer.is_server())
	# campfire_lit/extinguished 는 호스트에서만 발신한다 — 클라이언트 복제본도
	# 발신하면 랩터(호스트 소유 AI)가 불을 2개로 인식한다 (tests/props/test_net_campfire.gd).
	if _event_bus != null and multiplayer.is_server():
		_event_bus.campfire_lit.emit(self, global_position, config.light_radius)

func extinguish() -> void:
	if not is_lit:
		return

	is_lit = false
	fuel_remaining = 0.0
	set_process(false)
	if _event_bus != null and multiplayer.is_server():
		_event_bus.campfire_extinguished.emit(self)

func get_radius() -> float:
	return config.light_radius

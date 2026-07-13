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
	set_process(true)
	if _event_bus != null:
		_event_bus.campfire_lit.emit(self, global_position, config.light_radius)

func extinguish() -> void:
	if not is_lit:
		return

	is_lit = false
	fuel_remaining = 0.0
	set_process(false)
	if _event_bus != null:
		_event_bus.campfire_extinguished.emit(self)

func get_radius() -> float:
	return config.light_radius

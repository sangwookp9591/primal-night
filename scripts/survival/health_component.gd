class_name HealthComponent
extends Node

## 체력과 출혈. Player 에 자식 노드로 붙는다 (설계서 9.2: 규칙을 노드에 흩뿌리지 않는다).
## 출혈 중에만 _process 를 켠다 — 평상시 매 프레임 비용 0 (성능문서 6.1).

const DEFAULT_CONFIG: SurvivalConfig = preload("res://data/survival/survival_config.tres")

@export var config: SurvivalConfig = DEFAULT_CONFIG

var current_health: float = 0.0
var is_bleeding: bool = false

var _body: Node2D = null
var _event_bus: Node = null
var _smell_elapsed: float = 0.0

func _ready() -> void:
	# 매 프레임 노드 탐색 금지 (성능문서 6.1). 초기화 시 1회만 캐시한다.
	_body = get_parent() as Node2D
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	current_health = config.max_health
	set_process(false)

func _process(delta: float) -> void:
	if not is_bleeding:
		return

	take_damage(config.bleed_damage_per_second * delta, &"bleed")

	_smell_elapsed += delta
	if _smell_elapsed < config.bleed_smell_interval:
		return

	_smell_elapsed -= config.bleed_smell_interval
	if _event_bus != null and _body != null:
		_event_bus.smell_emitted.emit(_body.global_position, config.bleed_smell_strength, &"blood")

func take_damage(amount: float, kind: StringName = &"generic") -> void:
	if amount <= 0.0 or not is_alive():
		return

	current_health = maxf(current_health - amount, 0.0)
	if _event_bus != null:
		_event_bus.damage_taken.emit(_body, amount, kind)

	if not is_alive():
		stop_bleeding()

func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	current_health = minf(current_health + amount, config.max_health)

func start_bleeding() -> void:
	if is_bleeding or not is_alive():
		return

	is_bleeding = true
	_smell_elapsed = 0.0
	set_process(true)
	if _event_bus != null:
		_event_bus.bleeding_started.emit(_body)

func stop_bleeding() -> void:
	if not is_bleeding:
		return

	is_bleeding = false
	set_process(false)
	if _event_bus != null:
		_event_bus.bleeding_stopped.emit(_body)

func is_alive() -> bool:
	return current_health > 0.0

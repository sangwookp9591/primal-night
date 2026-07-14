class_name StaminaComponent
extends Node

## 스태미나. Player 에 자식 노드로 붙는다.
## Player 가 매 물리 프레임 update() 를 호출한다 (노드 탐색·할당 없음).

const DEFAULT_CONFIG: SurvivalConfig = preload("res://data/survival/survival_config.tres")

@export var config: SurvivalConfig = DEFAULT_CONFIG

var current_stamina: float = 0.0
## 소진되면 임계치까지 회복할 때까지 달리기가 잠긴다.
var is_exhausted: bool = false

func _ready() -> void:
	current_stamina = config.max_stamina

func can_run() -> bool:
	return not is_exhausted and current_stamina > 0.0

func update(running: bool, moving: bool, delta: float) -> void:
	if running and can_run():
		current_stamina = maxf(current_stamina - config.stamina_run_drain * delta, 0.0)
		if current_stamina <= 0.0:
			is_exhausted = true
		return

	var regen: float = config.stamina_regen_walk if moving else config.stamina_regen_idle
	current_stamina = minf(current_stamina + regen * delta, config.max_stamina)
	if is_exhausted and current_stamina >= config.stamina_recover_threshold:
		is_exhausted = false

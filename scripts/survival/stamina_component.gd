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

func try_spend(amount: float) -> bool:
	if amount <= 0.0 or current_stamina < amount:
		return false
	current_stamina -= amount
	if current_stamina <= 0.0:
		is_exhausted = true
	return true

## fatigue_ratio 는 0(쌩쌩)..1(탈진) 이다 (SurvivalStats.fatigue_ratio).
## 피로하면 같은 달리기에 스태미나를 더 쓰고 회복도 느리다 (설계서 5.1: 피로는 달리기에 영향).
## 기본값 0 이라 피로를 넘기지 않는 호출부는 기존 동작 그대로다.
func update(running: bool, moving: bool, delta: float, fatigue_ratio: float = 0.0,
		water_wellness: float = 1.0) -> void:
	var fatigue: float = clampf(fatigue_ratio, 0.0, 1.0)
	var dehydration: float = 1.0 - clampf(water_wellness, 0.0, 1.0)
	if running and can_run():
		var drain: float = config.stamina_run_drain * (1.0 + fatigue * config.fatigue_run_drain_bonus)
		current_stamina = maxf(current_stamina - drain * delta, 0.0)
		if current_stamina <= 0.0:
			is_exhausted = true
		return

	var regen: float = config.stamina_regen_walk if moving else config.stamina_regen_idle
	var regen_penalty: float = minf(fatigue * config.fatigue_regen_penalty
		+ dehydration * config.water_stamina_regen_penalty,
		config.stamina_regen_combined_penalty_cap)
	regen *= 1.0 - regen_penalty
	current_stamina = minf(current_stamina + regen * delta, config.max_stamina)
	if is_exhausted and current_stamina >= config.stamina_recover_threshold:
		is_exhausted = false

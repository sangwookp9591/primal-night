class_name SurvivalStats
extends Node

## 생존 수치 4종 (설계서 5.1): 체온 / 수분 / 포만 / 피로.
## Player 가 코드로 붙이는 자식 노드다 (HealthComponent 관례: 규칙을 Player 에 흩뿌리지 않는다).
##
## ★ 수치가 바닥나도 죽지 않는다 (설계서 5.1: "낮아졌다는 이유만으로 즉시 사망시키지 않는다").
##   체력을 직접 깎는 경로가 없다 — 악화는 단계 표시와 행동 효율로만 나타난다.
##
## 행동 효과:
##   피로 — 달리기 소모를 키우고 스태미나 회복을 늦춘다 (StaminaComponent).
##   체온 — 모닥불 곁에서만 회복한다.
##   수분 — 스태미나 회복을 늦춘다.
##   포만 — 자연 체력 회복을 늦춘다.
##
## 시뮬레이션은 호스트 권위다 (설계서 7.2). 클라이언트 복제본은 스스로 굴리지 않고
## NetSurvival 스냅샷으로만 맞춘다 — 양쪽이 각자 굴리면 값이 갈라진다.

const DEFAULT_CONFIG: SurvivalConfig = preload("res://data/survival/survival_config.tres")

## 네 수치 모두 0..100 이다. 피로만 방향이 반대다 — 높을수록 나쁘다.
const STAT_MAX: float = 100.0
const STATS: Array[StringName] = [&"temperature", &"water", &"food", &"fatigue"]

const STAGE_GOOD: StringName = &"양호"
const STAGE_WARN: StringName = &"주의"
const STAGE_DANGER: StringName = &"위험"

@export var config: SurvivalConfig = DEFAULT_CONFIG

var temperature: float = STAT_MAX
var water: float = STAT_MAX
var food: float = STAT_MAX
var fatigue: float = 0.0

var _body: Node2D = null
var _campfire_registry: Node = null
## 이동 거리로 피로를 쌓는다. 입력을 읽지 않으므로 원격 아바타에도 똑같이 적용된다
## (호스트는 남의 입력을 모르지만 남의 좌표는 안다).
var _last_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_body = get_parent() as Node2D
	if _body != null:
		_last_position = _body.global_position
	if has_node("/root/CampfireRegistry"):
		_campfire_registry = get_node("/root/CampfireRegistry")


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	simulate(delta)


## 한 틱 진행. 시간을 주입받는다 — 테스트 결정성 (SessionClock.advance 관례).
func simulate(delta: float) -> void:
	var moved: float = 0.0
	if _body != null:
		moved = _body.global_position.distance_to(_last_position)
		_last_position = _body.global_position

	water = maxf(water - config.water_drain_per_second * delta, 0.0)
	food = maxf(food - config.food_drain_per_second * delta, 0.0)
	if _body is Player:
		var player := _body as Player
		if player.health.is_alive() and not player.health.is_bleeding:
			player.health.heal(config.natural_health_regen_per_second
				* natural_health_regen_multiplier() * delta)

	if _near_fire():
		temperature = minf(temperature + config.temperature_regen_near_fire * delta, STAT_MAX)
	else:
		temperature = maxf(temperature - config.temperature_drain_per_second * delta, 0.0)

	# 움직이면 지치고(많이 움직일수록 더), 제자리에서 쉬면 풀린다.
	# 쉬는 것이 곧 회복이다 — 가만히 있는데도 지치면 플레이어에게 줄 선택지가 없다.
	if is_zero_approx(moved):
		fatigue = maxf(fatigue - config.fatigue_recover_per_second * delta, 0.0)
	else:
		fatigue = minf(fatigue + config.fatigue_gain_per_second * delta
			+ config.fatigue_gain_per_pixel * moved, STAT_MAX)


## 0(최악) .. 1(최상). 피로만 뒤집어 같은 경계로 단계를 매길 수 있게 한다.
func wellness_of(stat: StringName) -> float:
	match stat:
		&"fatigue":
			return 1.0 - fatigue / STAT_MAX
		&"water":
			return water / STAT_MAX
		&"food":
			return food / STAT_MAX
		_:
			return temperature / STAT_MAX


## 숫자 나열보다 단계 표시 (설계서 10.1). 경계는 SurvivalConfig 에서 온다.
func stage_of(stat: StringName) -> StringName:
	var wellness: float = wellness_of(stat)
	if wellness < config.stat_danger_ratio:
		return STAGE_DANGER
	if wellness < config.stat_warn_ratio:
		return STAGE_WARN
	return STAGE_GOOD


## 0(쌩쌩) .. 1(탈진). StaminaComponent 가 달리기 소모·회복에 곱한다.
func fatigue_ratio() -> float:
	return fatigue / STAT_MAX


func water_wellness() -> float:
	return water / STAT_MAX


func natural_health_regen_multiplier() -> float:
	var hunger: float = 1.0 - food / STAT_MAX
	return clampf(1.0 - hunger * config.food_health_regen_penalty, 0.0, 1.0)


func restore_food(amount: float) -> void:
	if amount > 0.0 and is_finite(amount):
		food = minf(food + amount, STAT_MAX)


func restore_water(amount: float) -> void:
	if amount > 0.0 and is_finite(amount):
		water = minf(water + amount, STAT_MAX)


## 호스트 확정 수치를 복제본에 적용한다 (NetSurvival 스냅샷 경로).
func apply_replicated(temperature_value: float, water_value: float,
		food_value: float, fatigue_value: float) -> void:
	temperature = clampf(temperature_value, 0.0, STAT_MAX)
	water = clampf(water_value, 0.0, STAT_MAX)
	food = clampf(food_value, 0.0, STAT_MAX)
	fatigue = clampf(fatigue_value, 0.0, STAT_MAX)


## 평면 배열 직렬화의 순서는 이 두 함수만 안다 (STATS 순서). NetSurvival 스냅샷이
## 쓴다 — 수치가 늘면 여기와 STATS 만 고치면 배열 경로는 따라온다.
func fill_into(target: PackedFloat32Array, base: int) -> void:
	target[base] = temperature
	target[base + 1] = water
	target[base + 2] = food
	target[base + 3] = fatigue


func apply_from(source: PackedFloat32Array, base: int) -> void:
	apply_replicated(source[base], source[base + 1], source[base + 2], source[base + 3])


func reset_motion_baseline() -> void:
	if _body != null:
		_last_position = _body.global_position


func _near_fire() -> bool:
	if _body == null:
		return false
	return _campfire_registry != null \
		and _campfire_registry.is_position_protected(_body.global_position)

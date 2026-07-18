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
const RAIN_WET_GAIN_PER_SECOND: float = 0.006
const DRY_PER_SECOND: float = 0.0025
const FIRE_DRY_PER_SECOND: float = 0.018
const WET_TEMPERATURE_DRAIN_BONUS: float = 2.0
const WET_FLAG: int = 1
const CLOTHING_SMELL_BASE: float = 3.0
const FOOD_POISON_DURATION_SECONDS: float = 90.0
const POISON_DURATION_SECONDS: float = 120.0
const FOOD_POISON_DRAIN_MULTIPLIER: float = 4.0
const VOMIT_INTERVAL_SECONDS: float = 12.0
const POISON_DAMAGE_PER_SECOND: float = 0.6

const STAGE_GOOD: StringName = &"양호"
const STAGE_WARN: StringName = &"주의"
const STAGE_DANGER: StringName = &"위험"

@export var config: SurvivalConfig = DEFAULT_CONFIG

var temperature: float = STAT_MAX
var water: float = STAT_MAX
var food: float = STAT_MAX
var fatigue: float = 0.0
var wetness: float = 0.0
var food_poison_remaining: float = 0.0
var poison_remaining: float = 0.0
var poison_potency: float = 0.0

var _body: Node2D = null
var _campfire_registry: Node = null
## 이동 거리로 피로를 쌓는다. 입력을 읽지 않으므로 원격 아바타에도 똑같이 적용된다
## (호스트는 남의 입력을 모르지만 남의 좌표는 안다).
var _last_position: Vector2 = Vector2.ZERO
var _rest_multiplier: float = 1.0
var _smell_grid: SmellGrid = null
var _vomit_elapsed: float = 0.0
var _status_elapsed: float = 0.0
var _noise_emitter := NoiseEmitter.new()
var _vomit_profile := NoiseProfile.new()
var _event_bus: Node = null
var _active_state_visual: StringName = &""


func _ready() -> void:
	_body = get_parent() as Node2D
	if _body != null:
		_last_position = _body.global_position
	if has_node("/root/CampfireRegistry"):
		_campfire_registry = get_node("/root/CampfireRegistry")
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	_vomit_profile.id = &"vomit"
	_vomit_profile.radius = 160.0
	_vomit_profile.merge_window_seconds = 1.0
	_vomit_profile.merge_distance_px = 24.0
	if _body is Player:
		var equipment := _body.get_node_or_null("EquipmentComponent") as EquipmentComponent
		if equipment != null:
			equipment.equipment_changed.connect(_on_equipment_changed)
		_refresh_clothing_smell.call_deferred()


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
	_simulate_food_safety(delta)
	if _body is Player:
		var player := _body as Player
		if player.health.is_alive() and not player.health.is_bleeding:
			player.health.heal(config.natural_health_regen_per_second
				* natural_health_regen_multiplier() * delta)

	_simulate_wetness(delta)
	var outfit := _outfit()
	var warmth := clampf(float(outfit.modifiers.get("warmth", 0.0)) if outfit != null else 0.0,
		0.0, 0.8)
	if _near_fire():
		temperature = minf(temperature + config.temperature_regen_near_fire * delta, STAT_MAX)
	else:
		var drain_multiplier := (1.0 - warmth * 0.6) \
			* (1.0 + wetness * WET_TEMPERATURE_DRAIN_BONUS)
		temperature = maxf(temperature
			- config.temperature_drain_per_second * drain_multiplier * delta, 0.0)

	# 움직이면 지치고(많이 움직일수록 더), 제자리에서 쉬면 풀린다.
	# 쉬는 것이 곧 회복이다 — 가만히 있는데도 지치면 플레이어에게 줄 선택지가 없다.
	if is_zero_approx(moved):
		fatigue = maxf(fatigue - config.fatigue_recover_per_second * _rest_multiplier * delta, 0.0)
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

func wet_run_drain_penalty() -> float:
	var outfit := _outfit()
	return wetness * (outfit.wet_weight_penalty if outfit != null else 0.15)


func natural_health_regen_multiplier() -> float:
	var hunger: float = 1.0 - food / STAT_MAX
	return clampf(1.0 - hunger * config.food_health_regen_penalty, 0.0, 1.0)


func restore_food(amount: float) -> void:
	if amount > 0.0 and is_finite(amount):
		food = minf(food + amount, STAT_MAX)


func restore_water(amount: float) -> void:
	if amount > 0.0 and is_finite(amount):
		water = minf(water + amount, STAT_MAX)


func apply_food_risk(food_poisoned: bool, potency: float) -> void:
	if food_poisoned:
		food_poison_remaining = maxf(food_poison_remaining, FOOD_POISON_DURATION_SECONDS)
		_vomit_elapsed = 0.0
	if potency > 0.0 and is_finite(potency):
		poison_potency = maxf(poison_potency, clampf(potency, 0.0, 1.0))
		poison_remaining = maxf(poison_remaining, POISON_DURATION_SECONDS)
	_refresh_state_visual()


func food_safety_snapshot() -> Dictionary:
	return {
		"food_poison_remaining": food_poison_remaining,
		"poison_remaining": poison_remaining,
		"poison_potency": poison_potency,
	}


func apply_food_safety_snapshot(state: Dictionary, death_recovery: bool = false) -> bool:
	if death_recovery:
		clear_food_safety()
		return true
	for key: String in ["food_poison_remaining", "poison_remaining", "poison_potency"]:
		if not state.has(key) or not (state[key] is float or state[key] is int) \
				or not is_finite(float(state[key])):
			return false
	food_poison_remaining = maxf(float(state.food_poison_remaining), 0.0)
	poison_remaining = maxf(float(state.poison_remaining), 0.0)
	poison_potency = clampf(float(state.poison_potency), 0.0, 1.0)
	_refresh_state_visual()
	return true


func clear_food_safety() -> void:
	food_poison_remaining = 0.0
	poison_remaining = 0.0
	poison_potency = 0.0
	_vomit_elapsed = 0.0
	_refresh_state_visual()


func _simulate_food_safety(delta: float) -> void:
	_status_elapsed += delta
	if food_poison_remaining > 0.0:
		food_poison_remaining = maxf(food_poison_remaining - delta, 0.0)
		water = maxf(water - config.water_drain_per_second
			* (FOOD_POISON_DRAIN_MULTIPLIER - 1.0) * delta, 0.0)
		food = maxf(food - config.food_drain_per_second
			* (FOOD_POISON_DRAIN_MULTIPLIER - 1.0) * delta, 0.0)
		_vomit_elapsed += delta
		if _vomit_elapsed >= VOMIT_INTERVAL_SECONDS:
			_vomit_elapsed -= VOMIT_INTERVAL_SECONDS
			if _body is Player:
				_noise_emitter.emit_profile(_event_bus, _vomit_profile,
					_body.global_position, _body, _status_elapsed, true)
	if poison_remaining > 0.0:
		poison_remaining = maxf(poison_remaining - delta, 0.0)
		if _body is Player:
			_record_status_cause(&"poison")
			(_body as Player).health.take_damage(
				POISON_DAMAGE_PER_SECOND * poison_potency * delta, &"poison")
		if poison_remaining <= 0.0:
			poison_potency = 0.0


func _record_status_cause(kind: StringName) -> void:
	var objective := get_tree().get_first_node_in_group(&"loop_objective")
	if objective != null and objective.has_method("record_cause_event"):
		objective.record_cause_event(kind, _body.global_position)

func set_rest_multiplier(value: float) -> void:
	_rest_multiplier = clampf(value, 1.0, 20.0) if is_finite(value) else 1.0


## 호스트 확정 수치를 복제본에 적용한다 (NetSurvival 스냅샷 경로).
func apply_replicated(temperature_value: float, water_value: float,
		food_value: float, fatigue_value: float, wetness_value: float = 0.0) -> void:
	temperature = clampf(temperature_value, 0.0, STAT_MAX)
	water = clampf(water_value, 0.0, STAT_MAX)
	food = clampf(food_value, 0.0, STAT_MAX)
	fatigue = clampf(fatigue_value, 0.0, STAT_MAX)
	wetness = clampf(wetness_value, 0.0, 1.0)
	_apply_wet_feedback()


## 평면 배열 직렬화의 순서는 이 두 함수만 안다 (STATS 순서). NetSurvival 스냅샷이
## 쓴다 — 수치가 늘면 여기와 STATS 만 고치면 배열 경로는 따라온다.
func fill_into(target: PackedFloat32Array, base: int) -> void:
	target[base] = temperature
	target[base + 1] = water
	target[base + 2] = food
	target[base + 3] = fatigue
	target[base + 4] = wetness


func apply_from(source: PackedFloat32Array, base: int) -> void:
	apply_replicated(source[base], source[base + 1], source[base + 2], source[base + 3],
		source[base + 4])


func reset_motion_baseline() -> void:
	if _body != null:
		_last_position = _body.global_position


func _near_fire() -> bool:
	if _body == null:
		return false
	return _campfire_registry != null \
		and _campfire_registry.is_position_protected(_body.global_position)

func _is_raining() -> bool:
	var weather := get_tree().get_first_node_in_group(&"weather") as NetWeather
	return weather != null and weather.raining

func _rain_intensity() -> float:
	var weather := get_tree().get_first_node_in_group(&"weather") as NetWeather
	return weather.intensity if weather != null else 0.0

func _outfit() -> WearableData:
	if not _body is Player:
		return null
	var equipment := _body.get_node_or_null("EquipmentComponent") as EquipmentComponent
	if equipment == null:
		return null
	var item_id := equipment.get_equipped(&"outfit")
	if item_id == &"":
		return null
	return get_node("/root/GameData").get_item(item_id) as WearableData

func _simulate_wetness(delta: float) -> void:
	var outfit := _outfit()
	if _is_raining():
		var wet_rate := RAIN_WET_GAIN_PER_SECOND * _rain_intensity() \
			* maxf(0.1, 1.0 + (outfit.wetness_modifier if outfit != null else 0.0))
		wetness = minf(wetness + wet_rate * delta, 1.0)
	else:
		var drying := outfit.drying_speed if outfit != null else 1.0
		var rate := FIRE_DRY_PER_SECOND if _near_fire() else DRY_PER_SECOND * drying
		wetness = maxf(wetness - rate * delta, 0.0)
	_apply_wet_feedback()

func _apply_wet_feedback() -> void:
	if not _body is Player:
		return
	var player := _body as Player
	if wetness >= 0.05:
		player.equipment.condition_flags |= WET_FLAG
	else:
		player.equipment.condition_flags &= ~WET_FLAG
	_refresh_state_visual()
	_refresh_clothing_smell()


func _refresh_state_visual() -> void:
	if not _body is Player:
		return
	var player := _body as Player
	if player.visual_rig == null:
		return
	var visual_id: StringName = &""
	if poison_remaining > 0.0 and poison_potency > 0.0:
		visual_id = &"poison_state"
	elif food_poison_remaining > 0.0:
		visual_id = &"food_poison_state"
	elif wetness >= 0.05:
		visual_id = &"placeholder_state_overlay"
	if visual_id != _active_state_visual:
		player.visual_rig.apply_visual(&"state_overlay", visual_id)
		_active_state_visual = visual_id
	if player.visual_rig.state_overlay != null:
		player.visual_rig.state_overlay.modulate.a = clampf(wetness, 0.2, 0.8) \
			if visual_id == &"placeholder_state_overlay" else 1.0

func _on_equipment_changed(_slot: StringName, _item_id: StringName) -> void:
	_refresh_clothing_smell()

func _refresh_clothing_smell() -> void:
	if not _body is Player or not is_inside_tree():
		return
	if _smell_grid == null:
		_smell_grid = SmellGrid.find_in(get_tree())
	if _smell_grid == null:
		return
	_smell_grid.unregister_smell_source(self)
	var player := _body as Player
	var outfit := _outfit()
	if outfit != null and outfit.smell_modifier > 0.0:
		_smell_grid.register_smell_source(self, Callable(self, "_smell_position"),
			CLOTHING_SMELL_BASE * outfit.smell_modifier * (1.0 + wetness),
			0.75, &"clothing")

func _smell_position() -> Vector2:
	return _body.global_position if _body != null else Vector2.ZERO

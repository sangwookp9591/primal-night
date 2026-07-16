class_name InjuryComponent
extends Node

## 플레이어별 부위 부상 상태. W6에서는 다리 열상만 활성 효과가 있다.

const BODY_PARTS: Array[StringName] = [&"head", &"torso", &"arm", &"leg"]
const LEG: StringName = &"leg"
const LACERATION: StringName = &"laceration"
const DEFAULT_CONFIG: SurvivalConfig = preload("res://data/survival/survival_config.tres")

var config: SurvivalConfig = DEFAULT_CONFIG

var body_part: StringName = &""
var injury_kind: StringName = &""

var _health: HealthComponent = null


func _ready() -> void:
	var player: Player = get_parent() as Player
	if player != null:
		_health = player.health


func is_valid_body_part(value: StringName) -> bool:
	return value in BODY_PARTS


## DamageSystem W6 최소 절편: 권위가 정한 다리 열상만 한 번에 커밋한다.
func apply_host_leg_laceration(damage: float) -> bool:
	if not multiplayer.is_server() or not is_finite(damage) or damage < 0.0 \
			or _health == null or not _health.is_alive():
		return false
	_health.take_damage(damage, &"laceration")
	if not _health.is_alive():
		return false
	body_part = LEG
	injury_kind = LACERATION
	_health.start_bleeding()
	return true


## 호스트 스냅샷 적용. 빈 쌍 또는 현재 지원하는 다리 열상만 허용한다.
func apply_replicated(part: StringName, kind: StringName) -> bool:
	if not is_valid_injury_state(part, kind):
		return false
	if part.is_empty():
		clear()
		return true
	body_part = part
	injury_kind = kind
	return true


func is_valid_injury_state(part: StringName, kind: StringName) -> bool:
	return (part.is_empty() and kind.is_empty()) or (part == LEG and kind == LACERATION)


func has_leg_laceration() -> bool:
	return body_part == LEG and injury_kind == LACERATION


func movement_multiplier() -> float:
	if not has_leg_laceration():
		return 1.0
	return config.leg_laceration_move_multiplier


func clear() -> void:
	body_part = &""
	injury_kind = &""

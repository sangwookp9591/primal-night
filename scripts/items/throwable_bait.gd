class_name ThrowableBait
extends Node2D

## 착지한 미끼. 물리 오브젝트 없이 소리 1회와 등록형 냄새 원천만 만든다.
## 냄새 값은 bait ItemData 에서 온다 (밸런스는 코드가 아니라 data/items/bait.tres 에서).
## emits_smell 은 켜지 않는다 — 보유·바닥 냄새(is_smell_source 경로)가 아니라
## 착지한 미끼만 냄새를 낸다.

const THROW_NOISE: NoiseProfile = preload("res://data/senses/noise_throw.tres")

var _event_bus: Node = null
var _noise_emitter: NoiseEmitter = NoiseEmitter.new()


func _ready() -> void:
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	var item: ItemData = get_node("/root/GameData").get_item(&"bait")
	var smell_source: SmellSource = SmellSource.new()
	smell_source.kind = item.get_smell_kind()
	smell_source.strength = item.smell_strength
	smell_source.interval_seconds = item.smell_interval_seconds
	add_child(smell_source)


func land_at(target_position: Vector2, source: Node) -> bool:
	if not target_position.is_finite():
		return false
	global_position = target_position
	return _noise_emitter.emit_profile(_event_bus, THROW_NOISE, global_position, source)

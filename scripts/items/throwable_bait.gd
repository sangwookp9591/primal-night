class_name ThrowableBait
extends Node2D

## 착지한 미끼. 물리 오브젝트 없이 소리 1회와 등록형 냄새 원천만 만든다.

const THROW_NOISE: NoiseProfile = preload("res://data/senses/noise_throw.tres")

@export var smell_kind: StringName = &"bait"
@export var smell_strength: float = 55.0
@export var smell_interval_seconds: float = 0.5

var _event_bus: Node = null
var _noise_emitter: NoiseEmitter = NoiseEmitter.new()
var _smell_source: SmellSource = null


func _ready() -> void:
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	_ensure_smell_source()


func land_at(target_position: Vector2, source: Node) -> bool:
	if not target_position.is_finite():
		return false
	global_position = target_position
	_ensure_smell_source()
	return _noise_emitter.emit_profile(_event_bus, THROW_NOISE, global_position, source,
		float(Time.get_ticks_msec()) / 1000.0)


func _ensure_smell_source() -> void:
	if _smell_source != null:
		return
	_smell_source = SmellSource.new()
	_smell_source.kind = smell_kind
	_smell_source.strength = smell_strength
	_smell_source.interval_seconds = smell_interval_seconds
	add_child(_smell_source)

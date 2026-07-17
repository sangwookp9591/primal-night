class_name RemoteNoiseLure
extends Node2D

## 스마트폰을 소진해 한 번 큰 소리를 내는 설치형 미끼.
## 설치와 발동은 권위 노드만 확정하며, 클라이언트 복제본은 시각 상태만 따른다.

const LURE_NOISE: NoiseProfile = preload("res://data/senses/noise_lure.tres")

@export_range(0.0, 60.0, 0.1) var trigger_delay_seconds: float = 2.0

var installed: bool = false
var spent: bool = false
var _event_bus: Node = null
var _installer: Node = null
var _noise_emitter := NoiseEmitter.new()
var _auto_trigger_remaining: float = -1.0


func _ready() -> void:
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")


## auto_trigger는 설치 지연 뒤 울리는 타이머 방식이다. false면 권위 측
## remote_trigger 호출을 기다린다.
func install_at(target_position: Vector2, source: Node, auto_trigger: bool = false) -> bool:
	if installed or spent or not target_position.is_finite() or not _has_authority(source):
		return false
	global_position = target_position
	_installer = source
	installed = true
	if auto_trigger:
		_auto_trigger_remaining = maxf(trigger_delay_seconds, 0.0)
	return true


func remote_trigger(source: Node) -> bool:
	if not installed or spent or source != _installer or not _has_authority(source):
		return false
	spent = true
	return _noise_emitter.emit_profile(_event_bus, LURE_NOISE, global_position, source)


func _physics_process(delta: float) -> void:
	if _auto_trigger_remaining < 0.0:
		return
	_auto_trigger_remaining -= delta
	if _auto_trigger_remaining <= 0.0:
		_auto_trigger_remaining = -1.0
		if is_instance_valid(_installer):
			remote_trigger(_installer)


func _has_authority(source: Node) -> bool:
	return multiplayer.is_server() and source != null and source.is_multiplayer_authority()

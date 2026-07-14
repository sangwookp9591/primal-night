class_name NoiseDebug
extends Node2D

## 소음 반경 디버그 시각화 (설계서 13장: 개발 빌드에서 소음 반경 표시).
## 디버그가 켜진 동안 noise_emitted 를 잠깐 원으로 보여준다.
## 소리는 물리 오브젝트가 아니라 이벤트 구조체다 (성능문서 5.3) — 여기서도 값만 기록한다.

const MARKER_SECONDS: float = 0.6
const MAX_MARKERS: int = 16

var debug_enabled: bool = false

## [{position, radius, remaining}] — 개수 상한이 있는 단순 배열.
var _markers: Array[Dictionary] = []

func _ready() -> void:
	set_process(false)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").noise_emitted.connect(_on_noise_emitted)

func _process(delta: float) -> void:
	var index: int = _markers.size() - 1
	while index >= 0:
		_markers[index].remaining -= delta
		if _markers[index].remaining <= 0.0:
			_markers.remove_at(index)
		index -= 1
	if _markers.is_empty():
		set_process(false)
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F4:
		debug_enabled = not debug_enabled
		if not debug_enabled:
			_markers.clear()
		queue_redraw()

func get_marker_count() -> int:
	return _markers.size()

func _on_noise_emitted(position: Vector2, radius: float, _source: Node) -> void:
	if not debug_enabled:
		return
	if _markers.size() >= MAX_MARKERS:
		_markers.remove_at(0)
	_markers.append({position = position, radius = radius, remaining = MARKER_SECONDS})
	set_process(true)

func _draw() -> void:
	if not debug_enabled:
		return
	for marker: Dictionary in _markers:
		var alpha: float = clampf(marker.remaining / MARKER_SECONDS, 0.0, 1.0) * 0.5
		draw_arc(to_local(marker.position), marker.radius, 0.0, TAU, 48, Color(1.0, 0.8, 0.1, alpha), 2.0)

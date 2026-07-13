extends CanvasLayer

const FrameMetricsScript = preload("res://scripts/debug/frame_metrics.gd")

@export var sample_capacity: int = 240
@export var refresh_interval_sec: float = 0.25

var _samples: PackedFloat64Array = PackedFloat64Array()
var _sample_index: int = 0
var _sample_count: int = 0
var _refresh_elapsed_sec: float = 0.0
var _visible_in_debug: bool = true
var _label: Label
var _calculator: RefCounted = FrameMetricsScript.new()

func _ready() -> void:
	if not OS.is_debug_build():
		visible = false
		set_process(false)
		return

	_samples.resize(sample_capacity)
	_label = Label.new()
	_label.name = "Metrics"
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)
	_refresh_text()

func _process(delta: float) -> void:
	record_frame_ms(delta * 1000.0)
	maybe_refresh(delta)

func _unhandled_input(event: InputEvent) -> void:
	handle_debug_toggle(event)

func handle_debug_toggle(event: InputEvent) -> bool:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode != KEY_F3:
		return false

	_visible_in_debug = not _visible_in_debug
	visible = _visible_in_debug
	return true

func record_frame_ms(frame_ms: float) -> void:
	if _samples.size() != sample_capacity:
		_samples.resize(sample_capacity)

	_samples[_sample_index] = frame_ms
	_sample_index = (_sample_index + 1) % sample_capacity
	_sample_count = mini(_sample_count + 1, sample_capacity)

func maybe_refresh(delta_sec: float) -> bool:
	_refresh_elapsed_sec += delta_sec
	if _refresh_elapsed_sec < refresh_interval_sec:
		return false

	_refresh_elapsed_sec = 0.0
	_refresh_text()
	return true

func get_recorded_sample_count() -> int:
	return _sample_count

func get_recorded_frame_ms() -> PackedFloat64Array:
	var ordered: PackedFloat64Array = PackedFloat64Array()
	ordered.resize(_sample_count)
	var start_index: int = 0
	if _sample_count == sample_capacity:
		start_index = _sample_index
	for output_index: int in range(_sample_count):
		ordered[output_index] = _samples[(start_index + output_index) % sample_capacity]
	return ordered

func _refresh_text() -> void:
	if _label == null:
		return

	var summary: Dictionary = _calculator.summarize(get_recorded_frame_ms())
	var frame_ms: Dictionary = summary["frame_ms"]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Frame ms now %.2f avg %.2f p95 %.2f" % [_latest_frame_ms(), _average_frame_ms(), frame_ms["p95"]])
	lines.append("Perf ai avg %.2f ms" % _perf_avg_ms(&"ai"))
	lines.append("Objects %.0f DrawCalls %.0f Memory %.1f MB" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		_get_draw_calls(),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	])
	_label.text = "\n".join(lines)

func _latest_frame_ms() -> float:
	if _sample_count == 0:
		return 0.0
	var latest_index: int = (_sample_index - 1 + sample_capacity) % sample_capacity
	return _samples[latest_index]

func _average_frame_ms() -> float:
	if _sample_count == 0:
		return 0.0
	var total_ms: float = 0.0
	for frame_ms: float in get_recorded_frame_ms():
		total_ms += frame_ms
	return total_ms / float(_sample_count)

func _perf_avg_ms(key: StringName) -> float:
	if not is_inside_tree() or not has_node("/root/PerfMonitor"):
		return 0.0
	return get_node("/root/PerfMonitor").get_avg_ms(key)

func _get_draw_calls() -> float:
	return Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

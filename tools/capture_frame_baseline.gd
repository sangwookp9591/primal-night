extends SceneTree

const FrameLogRecorderScript = preload("res://scripts/debug/frame_log_recorder.gd")
const FrameMetricsScript = preload("res://scripts/debug/frame_metrics.gd")

var _target_frames: int = 120
var _csv_path: String = "res://docs/technical/BASELINE_B01_HEADLESS_SMOKE.csv"
var _json_path: String = "res://docs/technical/BASELINE_B01_HEADLESS_SMOKE.json"
var _recorder: RefCounted = FrameLogRecorderScript.new()
var _calculator: RefCounted = FrameMetricsScript.new()
var _start_memory_mb: float = 0.0

func _initialize() -> void:
	_start_memory_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == "--frames" and index + 1 < args.size():
			_target_frames = int(args[index + 1])
		elif args[index] == "--csv" and index + 1 < args.size():
			_csv_path = args[index + 1]
		elif args[index] == "--json" and index + 1 < args.size():
			_json_path = args[index + 1]

func _process(delta: float) -> bool:
	_recorder.record_frame(delta * 1000.0)
	if _recorder.get_frames().size() < _target_frames:
		return false

	_write_outputs()
	quit(0)
	return true

func _write_outputs() -> void:
	_recorder.write_csv(_csv_path)

	var frames: PackedFloat64Array = _recorder.get_frames()
	var summary: Dictionary = _calculator.summarize(frames)
	var baseline: Dictionary = {
		"schema_version": 1,
		"engine": Engine.get_version_info()["string"],
		"build": _git_commit(),
		"hardware_id": "macos-dev-headless-not-minspec",
		"scenario": "B01_HEADLESS_SMOKE",
		"duration_sec": _duration_sec(frames),
		"measurement_note": "macOS 개발기 headless smoke 기준선이며 Windows 최소사양 예산 또는 출시 판정 수치가 아님.",
		"environment": _environment(),
		"frame_ms": summary["frame_ms"],
		"fps": summary["fps"],
		"stalls": summary["stalls"],
		"memory_mb": {
			"start": _start_memory_mb,
			"peak": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"end": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		},
		"custom": {
			"ai_update_usec_p95": 0.0,
			"scent_update_usec_p95": 0.0,
			"navigation_requests_max_frame": 0,
		},
	}

	var file: FileAccess = FileAccess.open(_json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(baseline, "\t"))
		file.store_string("\n")

func _duration_sec(frames: PackedFloat64Array) -> float:
	var total_ms: float = 0.0
	for frame_ms: float in frames:
		total_ms += frame_ms
	return total_ms / 1000.0

func _environment() -> Dictionary:
	return {
		"os": OS.get_name(),
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": "headless",
		"display_server": DisplayServer.get_name(),
	}

func _git_commit() -> String:
	var output: Array = []
	var code: int = OS.execute("git", PackedStringArray(["rev-parse", "--short", "HEAD"]), output, true)
	if code != 0 or output.is_empty():
		return "unknown"
	var commit: String = String(output[0]).strip_edges()
	var status_output: Array = []
	var status_code: int = OS.execute("git", PackedStringArray(["status", "--porcelain"]), status_output, true)
	if status_code == 0 and not status_output.is_empty() and not String(status_output[0]).strip_edges().is_empty():
		return "%s-dirty" % commit
	return commit

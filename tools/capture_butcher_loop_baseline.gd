extends SceneTree

## W5~6 해체 루프 성능 기준선 캡처 (계획서 W5-T9, 성능문서 9장).
## 실행:
##   /opt/homebrew/bin/godot --headless --path . -s tools/capture_butcher_loop_baseline.gd
##   (프레임 수 조정: -- --frames 2400)
##
## W3~4 기준선(BASELINE_W3_4_SENSE_LOOP)은 랩터 1마리 + 출혈 피 냄새(강도 60)뿐이었다.
## W5 에서 랩터가 2마리로 늘고 사체 피 냄새가 80 까지 올라갔으므로, 그 기준선을 그대로
## 두면 "기능은 늘었는데 예산은 옛날 씬" 인 가짜 통과가 된다. 이 시나리오는 실제로:
##   랩터 2마리(PackCoordinator) + 사체 신선 냄새 80 + 반복 해체 구간(절단 소음·냄새 갱신)
## 을 태워 냄새 활성 셀과 AI/scent p95 를 다시 잰다.
##
## ★ 개발기 headless 수치다. Windows 최소사양 예산도, 출시 판정도 아니다 (성능문서 10장).
##   여기서 지키는 것은 회귀 폭과 CPU 예산 상한뿐이다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")
const FrameLogRecorderScript = preload("res://scripts/debug/frame_log_recorder.gd")
const FrameMetricsScript = preload("res://scripts/debug/frame_metrics.gd")

## PerfMonitor 링 버퍼(60샘플)를 채울 만큼 길게 돈다 (콜드스타트가 p95 를 지배하지 않도록).
const DEFAULT_FRAMES: int = 2000
## 새 사체를 놓고 다시 해체를 돌리는 주기 (프레임). 절단 소음·냄새 갱신을 반복 태운다.
const BUTCHER_CYCLE_FRAMES: int = 90

var _target_frames: int = DEFAULT_FRAMES
var _csv_path: String = "res://docs/technical/BASELINE_W5_6_BUTCHER.csv"
var _json_path: String = "res://docs/technical/BASELINE_W5_6_BUTCHER.json"

var _recorder: RefCounted = FrameLogRecorderScript.new()
var _calculator: RefCounted = FrameMetricsScript.new()
var _start_memory_mb: float = 0.0
var _peak_memory_mb: float = 0.0

var _main: Node2D = null
var _player: Player = null
var _raptor: Raptor = null
var _raptor2: Raptor = null
var _grid: SmellGrid = null
var _demo: Node2D = null
var _perf: Node = null
var _frame: int = 0

var _active_cells_max: int = 0
var _investigate_entries: int = 0
var _chase_entries: int = 0
var _butcher_stages: int = 0
var _carcasses_spawned: int = 0
var _active_carcass: Carcass = null


func _initialize() -> void:
	_parse_args()
	_start_memory_mb = _memory_mb()
	_peak_memory_mb = _start_memory_mb
	_perf = get_root().get_node("PerfMonitor")

	_main = MainScene.instantiate()
	get_root().add_child(_main)
	_player = _main.get_node("Player")
	_raptor = _main.get_node("Raptor")
	_raptor2 = _main.get_node("Raptor2")
	_grid = _main.get_node("SmellGrid")
	_demo = _main.get_node("SurvivalDemo")
	# 시드를 고정한다 — 배회·훑기 목표가 매 실행 달라지면 기준선이 흔들린다.
	_raptor.rng.seed = 5001
	_raptor2.rng.seed = 5101
	_raptor.state_changed.connect(_on_raptor_state)
	_raptor2.state_changed.connect(_on_raptor_state)


func _on_raptor_state(_previous: int, next: int) -> void:
	if next == Raptor.State.INVESTIGATE:
		_investigate_entries += 1
	elif next == Raptor.State.CHASE:
		_chase_entries += 1


func _process(delta: float) -> bool:
	_recorder.record_frame(delta * 1000.0)
	_peak_memory_mb = maxf(_peak_memory_mb, _memory_mb())
	_active_cells_max = maxi(_active_cells_max, _grid.get_active_cell_count())

	# ★ @onready(Player.inventory 등)는 _initialize 시점엔 null 이라 첫 프레임에 시동한다.
	if _frame == 1:
		_player.inventory.add_item(&"stone_knife", 1)
		# 두 랩터를 사체 근처(시야 밖·소음 반경 안)에 두어 조사/무리 조율을 태운다.
		var seed_carcass: Carcass = _main.get_node("SurvivalDemo/RaptorCarcass")
		_raptor.global_position = seed_carcass.global_position + Vector2(210.0, 0.0)
		_raptor2.global_position = seed_carcass.global_position + Vector2(-210.0, 60.0)

	# 주기적으로 새 사체를 놓고 한 구간씩 해체한다 — 절단 소음(240px)과 신선 피 냄새(80)를
	# 반복해서 격자·AI 에 태운다. 사체가 골격이 되면 다음 사체로 넘어간다.
	if _frame % BUTCHER_CYCLE_FRAMES == 0:
		_ensure_active_carcass()
	elif _active_carcass != null and is_instance_valid(_active_carcass) \
			and not _active_carcass.is_fully_butchered() and _frame % 12 == 0:
		_player.global_position = _active_carcass.global_position
		if _active_carcass.apply_stage(_player):
			_butcher_stages += 1

	_frame += 1
	if _recorder.get_frames().size() < _target_frames:
		return false

	_write_outputs()
	quit(0)
	return true


func _ensure_active_carcass() -> void:
	# 직전 사체를 치우고 새로 놓는다 — 한 킬 사이트에 사체 1~2구가 겹치는 현실적인
	# 최악을 태운다. 무한히 쌓으면(23구) 활성 셀이 실제 플레이와 무관하게 부풀어
	# 회귀 게이트가 과하게 헐거워진다.
	if _active_carcass != null and is_instance_valid(_active_carcass):
		_active_carcass.queue_free()
	var carcass: Carcass = CarcassScene.instantiate()
	carcass.name = "BaselineCarcass%d" % _carcasses_spawned
	var angle: float = float(_carcasses_spawned) * 1.3
	carcass.position = Vector2(-300.0, 300.0) + Vector2.from_angle(angle) * 180.0
	_demo.add_child(carcass)
	_carcasses_spawned += 1
	_active_carcass = carcass


func _write_outputs() -> void:
	_recorder.write_csv(_csv_path)
	var frames: PackedFloat64Array = _recorder.get_frames()
	var summary: Dictionary = _calculator.summarize(frames)
	var baseline: Dictionary = {
		"schema_version": 1,
		"engine": Engine.get_version_info()["string"],
		"build": _git_commit(),
		"hardware_id": "macos-dev-headless-not-minspec",
		"scenario": "W5_6_BUTCHER_LOOP",
		"duration_sec": _duration_sec(frames),
		"measurement_note": "macOS 개발기 headless 해체 루프 기준선이며 Windows 최소사양 예산 또는 출시 판정 수치가 아님 (성능문서 10장). 로컬 회귀 게이트 전용.",
		"scenario_note": "main.tscn 실주행: 랩터 2마리(PackCoordinator) + 반복 사체 해체(절단 소음 240px·신선 피 냄새 80) + 냄새 격자 갱신. 랩터 rng seed=5001/5101 고정.",
		"environment": _environment(),
		"frame_ms": summary["frame_ms"],
		"fps": summary["fps"],
		"stalls": summary["stalls"],
		"memory_mb": {
			"start": _start_memory_mb,
			"peak": _peak_memory_mb,
			"end": _memory_mb(),
		},
		"custom": {
			"ai_update_ms_p95": _perf.get_p95_ms(&"ai"),
			"ai_update_ms_max": _perf.get_max_ms(&"ai"),
			"ai_samples": _perf.get_sample_count(&"ai"),
			"scent_update_ms_p95": _perf.get_p95_ms(&"scent"),
			"scent_update_ms_max": _perf.get_max_ms(&"scent"),
			"scent_samples": _perf.get_sample_count(&"scent"),
			"noise_emit_ms_p95": _perf.get_p95_ms(&"noise"),
			"noise_emit_ms_max": _perf.get_max_ms(&"noise"),
			"noise_samples": _perf.get_sample_count(&"noise"),
			"smell_active_cells_max": _active_cells_max,
			"raptor_investigate_entries": _investigate_entries,
			"raptor_chase_entries": _chase_entries,
			"butcher_stages_total": _butcher_stages,
			"carcasses_spawned": _carcasses_spawned,
		},
	}
	var file: FileAccess = FileAccess.open(_json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(baseline, "\t"))
		file.store_string("\n")
	print("기준선 기록: %s / %s" % [_json_path, _csv_path])
	print("  frame p95=%.3fms  ai p95=%.3fms(%d샘플)  scent p95=%.3fms(%d샘플)  활성셀 최대=%d  해체구간=%d  조사진입=%d" % [
		float(summary["frame_ms"]["p95"]), _perf.get_p95_ms(&"ai"), _perf.get_sample_count(&"ai"),
		_perf.get_p95_ms(&"scent"), _perf.get_sample_count(&"scent"),
		_active_cells_max, _butcher_stages, _investigate_entries])


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == "--frames" and index + 1 < args.size():
			_target_frames = int(args[index + 1])
		elif args[index] == "--csv" and index + 1 < args.size():
			_csv_path = args[index + 1]
		elif args[index] == "--json" and index + 1 < args.size():
			_json_path = args[index + 1]


func _memory_mb() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0


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

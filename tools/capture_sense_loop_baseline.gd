extends SceneTree

## W3~4 감지 루프 성능 기준선 캡처 (계획서 W4-T5, 성능문서 9장).
## 실행:
##   /opt/homebrew/bin/godot --headless --path . -s tools/capture_sense_loop_baseline.gd
##   (프레임 수 조정: -- --frames 600)
##
## B01_HEADLESS_SMOKE 는 빈 메인 씬을 그냥 돌린 스모크였다. 이 시나리오는 W3~4 에서
## 추가된 것들을 실제로 태운다: 출혈 → 피 냄새 격자 → 바람 이류 → 랩터 조사/훑기 →
## 세션 시계 → 생존 수치. 그래야 "기능은 늘었는데 기준선은 빈 씬" 인 가짜 통과가 안 된다.
##
## ★ 개발기 headless 수치다. Windows 최소사양 예산도, 출시 판정도 아니다 (성능문서 10장).
##   여기서 지키는 것은 회귀 폭과 CPU 예산 상한뿐이다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const NoiseEmitterScript = preload("res://scripts/senses/noise_emitter.gd")
const NoiseProfileScript = preload("res://scripts/senses/noise_profile.gd")
const FrameLogRecorderScript = preload("res://scripts/debug/frame_log_recorder.gd")
const FrameMetricsScript = preload("res://scripts/debug/frame_metrics.gd")

## PerfMonitor 링 버퍼(60샘플)를 채울 만큼 길게 돈다. 짧게 끊으면 첫 틱의 콜드스타트가
## p95 를 지배해 기준선이 실제보다 10배 나빠 보인다 (초기 캡처에서 scent p95 0.85ms →
## 링을 채우면 0.05ms). 2000프레임 ≈ 14초 ≈ 냄새 틱 56회.
const DEFAULT_FRAMES: int = 2000
## 주기적으로 소리를 내 랩터를 조사로 끌어들인다 (프레임 간격).
const NOISE_INTERVAL_FRAMES: int = 45
## 플레이어가 랩터 쪽으로 접근하는 속도(px/프레임). 결국 시야에 들어가 추격까지 태운다 —
## 배회만 도는 씬을 기준선으로 삼으면 AI 예산을 측정한 척만 하는 것이다.
const APPROACH_STEP: Vector2 = Vector2(-0.25, 0.35)

var _target_frames: int = DEFAULT_FRAMES
var _csv_path: String = "res://docs/technical/BASELINE_W3_4_SENSE_LOOP.csv"
var _json_path: String = "res://docs/technical/BASELINE_W3_4_SENSE_LOOP.json"

var _recorder: RefCounted = FrameLogRecorderScript.new()
var _calculator: RefCounted = FrameMetricsScript.new()
var _start_memory_mb: float = 0.0
var _peak_memory_mb: float = 0.0

var _main: Node2D = null
var _player: Player = null
var _raptor: Raptor = null
var _grid: SmellGrid = null
var _perf: Node = null
var _frame: int = 0

## 시나리오 관측치.
var _noise_events: int = 0
var _active_cells_max: int = 0
var _investigate_entries: int = 0
var _chase_entries: int = 0
var _noise_emitter: NoiseEmitter = NoiseEmitterScript.new()
var _noise_profile: NoiseProfile = null


func _initialize() -> void:
	_parse_args()
	_start_memory_mb = _memory_mb()
	_peak_memory_mb = _start_memory_mb

	_perf = get_root().get_node("PerfMonitor")
	_noise_profile = NoiseProfileScript.new()
	_noise_profile.id = &"sense_loop_baseline"
	_noise_profile.radius = 400.0
	_noise_profile.merge_window_seconds = 0.0
	_noise_profile.merge_distance_px = 0.0
	get_root().get_node("EventBus").noise_emitted.connect(
		func(_position: Vector2, _radius: float, _source: Node) -> void: _noise_events += 1)

	_main = MainScene.instantiate()
	get_root().add_child(_main)
	_player = _main.get_node("Player")
	_raptor = _main.get_node("Raptor")
	_grid = _main.get_node("SmellGrid")
	# 시드를 고정한다 — 배회·훑기 목표가 매 실행 달라지면 기준선이 흔들린다.
	_raptor.rng.seed = 4001
	_raptor.state_changed.connect(func(_previous: int, next: int) -> void:
		if next == Raptor.State.INVESTIGATE:
			_investigate_entries += 1
		elif next == Raptor.State.CHASE:
			_chase_entries += 1)


func _process(delta: float) -> bool:
	# ★ 시나리오 시동은 첫 프레임에 한다 — _initialize 시점에는 씬의 @onready
	# (Player.health 등)가 아직 풀리지 않아 null 이다.
	# 출혈이 피 냄새를 만들고, 그 냄새가 랩터를 부른다 (설계서 5.2/5.4).
	if not _player.health.is_bleeding and _frame == 0:
		_player.health.start_bleeding()

	_recorder.record_frame(delta * 1000.0)
	_peak_memory_mb = maxf(_peak_memory_mb, _memory_mb())
	_active_cells_max = maxi(_active_cells_max, _grid.get_active_cell_count())

	# 플레이어가 랩터 쪽으로 조금씩 다가간다 — 피 냄새를 흘리며 이동하고(생존 수치·냄새
	# 격자), 끝에는 시야에 들어가 추격까지 태운다.
	_player.global_position += APPROACH_STEP

	# 랩터 근처에 주기적으로 소리를 낸다. 매번 다른 지점이라 조사 → 훑기 → 재탐색이
	# 실제로 돌아간다 (W3-T6 경로). 지점은 프레임에서 유도해 결정적이다.
	if _frame % NOISE_INTERVAL_FRAMES == 0:
		var step: int = _frame / NOISE_INTERVAL_FRAMES
		var offset: Vector2 = Vector2.from_angle(float(step) * 1.1) * 240.0
		_noise_emitter.emit_profile(get_root().get_node("EventBus"), _noise_profile,
			_raptor.global_position + offset, null, float(_frame) / 60.0, false)

	_frame += 1
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
		"scenario": "W3_4_SENSE_LOOP",
		"duration_sec": _duration_sec(frames),
		"measurement_note": "macOS 개발기 headless 감지 루프 기준선이며 Windows 최소사양 예산 또는 출시 판정 수치가 아님 (성능문서 10장). 로컬 회귀 게이트 전용.",
		"scenario_note": "main.tscn 실주행: 출혈→피 냄새→바람 이류→랩터 조사/훑기→세션 시계→생존 수치. 랩터 rng seed=4001 고정.",
		"environment": _environment(),
		"frame_ms": summary["frame_ms"],
		"fps": summary["fps"],
		"stalls": summary["stalls"],
		"memory_mb": {
			"start": _start_memory_mb,
			"peak": _peak_memory_mb,
			"end": _memory_mb(),
		},
		# 성능문서 4.2 CPU 예산에 대응하는 커스텀 모니터. 샘플 수를 함께 남긴다 —
		# 0.0ms 가 "빨라서" 인지 "계측이 빠져서" 인지 구분할 근거다.
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
			"noise_events_total": _noise_events,
			"raptor_investigate_entries": _investigate_entries,
			"raptor_chase_entries": _chase_entries,
		},
	}

	var file: FileAccess = FileAccess.open(_json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(baseline, "\t"))
		file.store_string("\n")
	print("기준선 기록: %s / %s" % [_json_path, _csv_path])
	print("  frame p95=%.3fms  ai p95=%.3fms(%d샘플)  scent p95=%.3fms(%d샘플)  noise p95=%.3fms(%d샘플)  활성셀 최대=%d  소리 이벤트=%d" % [
		float(summary["frame_ms"]["p95"]), _perf.get_p95_ms(&"ai"), _perf.get_sample_count(&"ai"),
		_perf.get_p95_ms(&"scent"), _perf.get_sample_count(&"scent"),
		_perf.get_p95_ms(&"noise"), _perf.get_sample_count(&"noise"),
		_active_cells_max, _noise_events])


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

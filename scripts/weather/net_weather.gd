class_name NetWeather
extends CanvasLayer

signal weather_changed(raining: bool, intensity: float)

const RAIN_DURATION_SECONDS: float = 105.0
const WARNING_SECONDS: float = 25.0
const DEFAULT_SESSION_SEED: int = 731_941

@export var clock_path: NodePath = ^"../SessionClock"
@export var session_seed: int = DEFAULT_SESSION_SEED

var raining: bool = false
var intensity: float = 0.0
var warning_strength: float = 0.0
var schedule: Array[Vector2] = []
var _clock: SessionClock
var _overlay: ColorRect

func _ready() -> void:
	add_to_group(&"weather")
	_clock = get_node(clock_path) as SessionClock
	schedule = build_schedule(session_seed, _clock.day_duration_seconds(), _clock.total_days)
	_overlay = ColorRect.new()
	_overlay.name = "RainOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_apply_visuals()

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	var elapsed := float(_clock.current_day - 1) * _clock.day_duration_seconds() \
		+ _clock.time_of_day_seconds
	var next_raining := false
	var next_intensity := 0.0
	var next_warning := 0.0
	for window: Vector2 in schedule:
		if elapsed >= window.x and elapsed < window.y:
			next_raining = true
			var edge := minf(elapsed - window.x, window.y - elapsed)
			next_intensity = clampf(edge / 12.0, 0.25, 1.0)
			break
		if elapsed < window.x:
			next_warning = clampf(1.0 - (window.x - elapsed) / WARNING_SECONDS, 0.0, 1.0)
			break
	if next_raining != raining or not is_equal_approx(next_intensity, intensity) \
			or absf(next_warning - warning_strength) >= 0.02:
		apply_weather(next_raining, next_intensity, next_warning)
		if multiplayer.get_peers().size() > 0:
			apply_weather.rpc(next_raining, next_intensity, next_warning)
	else:
		warning_strength = next_warning
		_apply_visuals()

@rpc("authority", "call_remote", "unreliable_ordered")
func apply_weather(is_raining: bool, rain_intensity: float, warning: float = 0.0) -> void:
	raining = is_raining
	intensity = clampf(rain_intensity, 0.0, 1.0)
	warning_strength = clampf(warning, 0.0, 1.0)
	_apply_visuals()
	weather_changed.emit(raining, intensity)

func snapshot() -> Dictionary:
	return {"seed": session_seed, "raining": raining, "intensity": intensity,
		"warning": warning_strength}

func apply_snapshot(state: Dictionary) -> void:
	session_seed = int(state.get("seed", DEFAULT_SESSION_SEED))
	schedule = build_schedule(session_seed, _clock.day_duration_seconds(), _clock.total_days)
	apply_weather(bool(state.get("raining", false)), float(state.get("intensity", 0.0)),
		float(state.get("warning", 0.0)))

static func build_schedule(seed_value: int, day_seconds: float, days: int) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array[Vector2] = []
	var count := 1 + int(rng.randi() % 2)
	var session_seconds := day_seconds * float(days)
	for index: int in range(count):
		var band_start := session_seconds * (0.18 + 0.44 * float(index))
		var start := band_start + rng.randf_range(0.0, session_seconds * 0.16)
		result.append(Vector2(start, minf(start + RAIN_DURATION_SECONDS, session_seconds)))
	return result

func _apply_visuals() -> void:
	if _overlay == null:
		return
	var darkness := maxf(intensity * 0.18, warning_strength * 0.10)
	_overlay.color = Color(0.04, 0.09, 0.16, darkness)
	_overlay.visible = darkness > 0.001

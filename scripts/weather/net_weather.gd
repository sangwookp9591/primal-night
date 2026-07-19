class_name NetWeather
extends CanvasLayer

signal weather_changed(raining: bool, intensity: float)

const RAIN_DURATION_SECONDS: float = 105.0
const WARNING_SECONDS: float = 25.0
const DEFAULT_SESSION_SEED: int = 731_941
const MAX_RAIN_STREAKS: int = 180
const MAX_RAIN_SPLASHES: int = 48

@export var clock_path: NodePath = ^"../SessionClock"
@export var session_seed: int = DEFAULT_SESSION_SEED

var raining: bool = false
var intensity: float = 0.0
var warning_strength: float = 0.0
var schedule: Array[Vector2] = []
var _clock: SessionClock
var _overlay: ColorRect
var _rain_streaks: CPUParticles2D
var _rain_splashes: CPUParticles2D
var _wet_vignette: TextureRect

func _ready() -> void:
	add_to_group(&"weather")
	_clock = get_node(clock_path) as SessionClock
	schedule = build_schedule(session_seed, _clock.day_duration_seconds(), _clock.total_days)
	_overlay = ColorRect.new()
	_overlay.name = "RainOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_create_rain_particles()
	_apply_visuals()


func _create_rain_particles() -> void:
	var streak_texture := ParticleFactory.make_soft_texture(
		Color(0.68, 0.79, 0.9, 0.45), Color.TRANSPARENT, Vector2i(3, 28))
	_rain_streaks = ParticleFactory.add_particles(self, &"RainStreaks", MAX_RAIN_STREAKS,
		0.75, streak_texture)
	_rain_streaks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain_streaks.direction = Vector2(-0.28, 1.0).normalized()
	_rain_streaks.spread = 3.0
	_rain_streaks.initial_velocity_min = 650.0
	_rain_streaks.initial_velocity_max = 820.0
	_rain_streaks.scale_amount_min = 0.18
	_rain_streaks.scale_amount_max = 0.38

	_rain_splashes = ParticleFactory.add_particles(self, &"RainSplashes", MAX_RAIN_SPLASHES,
		0.22, ParticleFactory.make_soft_texture(Color(0.64, 0.78, 0.88, 0.34)))
	_rain_splashes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain_splashes.direction = Vector2.UP
	_rain_splashes.spread = 72.0
	_rain_splashes.initial_velocity_min = 24.0
	_rain_splashes.initial_velocity_max = 58.0
	_rain_splashes.gravity = Vector2(0.0, 260.0)
	_rain_splashes.scale_amount_min = 0.18
	_rain_splashes.scale_amount_max = 0.42

	_wet_vignette = TextureRect.new()
	_wet_vignette.name = "WetVignette"
	_wet_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wet_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wet_vignette.texture = ParticleFactory.make_soft_texture(
		Color(0.02, 0.07, 0.11, 0.0), Color(0.02, 0.07, 0.11, 0.22), Vector2i(256, 144))
	_wet_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_wet_vignette)

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
	# intensity 도 warning 처럼 스텝 양자화한다 — 램프 구간에서 매 물리틱
	# RPC 가 발사되는 것을 막는다 (변화 폭이 유의미할 때만 전파).
	if next_raining != raining or absf(next_intensity - intensity) >= 0.02 \
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
	if _rain_streaks == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var effective := intensity if raining else 0.0
	_rain_streaks.position = Vector2(viewport_size.x * 0.5, -32.0)
	_rain_streaks.emission_rect_extents = Vector2(viewport_size.x * 0.58, 24.0)
	_rain_splashes.position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.88)
	_rain_splashes.emission_rect_extents = Vector2(viewport_size.x * 0.52, 5.0)
	# set_amount 는 같은 값이어도 파티클 버퍼를 리셋한다 — 변할 때만 대입.
	var streak_amount := clampi(roundi(MAX_RAIN_STREAKS * maxf(effective, 0.25)),
		1, MAX_RAIN_STREAKS)
	if _rain_streaks.amount != streak_amount:
		_rain_streaks.amount = streak_amount
	var splash_amount := clampi(roundi(MAX_RAIN_SPLASHES * maxf(effective, 0.25)),
		1, MAX_RAIN_SPLASHES)
	if _rain_splashes.amount != splash_amount:
		_rain_splashes.amount = splash_amount
	_rain_streaks.emitting = raining
	_rain_splashes.emitting = raining
	_wet_vignette.visible = raining
	_wet_vignette.modulate.a = 0.35 + 0.45 * effective

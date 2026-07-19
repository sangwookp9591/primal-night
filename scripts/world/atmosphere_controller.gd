class_name AtmosphereController
extends Node

const DAY_COLOR := Color(1.0, 0.96, 0.88, 1.0)
const DUSK_COLOR := Color(0.86, 0.56, 0.34, 1.0)
const NIGHT_COLOR := Color(0.16, 0.22, 0.38, 1.0)
const DAWN_COLOR := Color(0.48, 0.57, 0.68, 1.0)
const DAWN_SECONDS: float = 45.0
const TRANSITION_SPEED: float = 0.45
const TORCH_SCAN_SECONDS: float = 0.25
const MAX_DYNAMIC_LIGHTS: int = 12

@export var clock_path: NodePath = ^"../SessionClock"
@export var weather_path: NodePath = ^"../NetWeather"
@export var canvas_modulate_path: NodePath = ^"../WorldTint"

var _clock: SessionClock
var _weather: NetWeather
var _canvas_modulate: CanvasModulate
var _rain_intensity: float = 0.0
var _torch_scan_elapsed: float = 0.0
var _elapsed: float = 0.0


func _ready() -> void:
	_clock = get_node(clock_path) as SessionClock
	_weather = get_node_or_null(weather_path) as NetWeather
	_canvas_modulate = get_node(canvas_modulate_path) as CanvasModulate
	if _weather != null:
		_weather.weather_changed.connect(_on_weather_changed)
		_rain_intensity = _weather.intensity if _weather.raining else 0.0
	_canvas_modulate.color = target_color()


func _process(delta: float) -> void:
	_elapsed += delta
	_canvas_modulate.color = _canvas_modulate.color.lerp(target_color(),
		clampf(delta * TRANSITION_SPEED, 0.0, 1.0))
	_torch_scan_elapsed += delta
	if _torch_scan_elapsed >= TORCH_SCAN_SECONDS:
		_torch_scan_elapsed = 0.0
		_refresh_torch_lights()
	var index := 0
	for node: Node in get_tree().get_nodes_in_group(&"atmosphere_light"):
		var light := node as PointLight2D
		if light == null:
			continue
		light.energy = float(light.get_meta(&"base_energy", 1.0)) \
			* (1.0 + sin(_elapsed * 6.7 + float(index) * 1.9) * 0.035)
		index += 1


func target_color() -> Color:
	var base := phase_color(_clock.current_phase, _clock.time_of_day_seconds) \
		if _clock != null else DAY_COLOR
	if _rain_intensity <= 0.0:
		return base
	var gray := Color(base.get_luminance(), base.get_luminance(), base.get_luminance(), 1.0)
	var rainy := base.lerp(gray, _rain_intensity * 0.12) * (1.0 - _rain_intensity * 0.08)
	rainy.a = 1.0
	return rainy


static func phase_color(phase: SessionClock.Phase, time_of_day: float = 0.0) -> Color:
	match phase:
		SessionClock.Phase.DUSK:
			return DUSK_COLOR
		SessionClock.Phase.NIGHT:
			return NIGHT_COLOR
		_:
			if time_of_day < DAWN_SECONDS:
				return DAWN_COLOR.lerp(DAY_COLOR, clampf(time_of_day / DAWN_SECONDS, 0.0, 1.0))
			return DAY_COLOR


static func create_point_light(owner: Node, light_name: String,
		radius_scale: float, energy: float = 1.0) -> PointLight2D:
	var existing := owner.get_node_or_null(NodePath(light_name)) as PointLight2D
	if existing != null:
		return existing
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 0.78, 0.42, 1), Color(1, 0.42, 0.12, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var light := PointLight2D.new()
	light.name = light_name
	light.texture = texture
	light.texture_scale = radius_scale
	light.color = Color(1.0, 0.72, 0.38)
	light.energy = energy
	light.set_meta(&"base_energy", energy)
	light.shadow_enabled = false
	light.add_to_group(&"atmosphere_light")
	owner.add_child(light)
	return light


func _refresh_torch_lights() -> void:
	var count := get_tree().get_nodes_in_group(&"atmosphere_light").size()
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null:
			continue
		var light := player.get_node_or_null("HeldTorchLight") as PointLight2D
		var held := player.equipment.get_equipped(&"main_hand") == &"torch"
		if light == null and held and count < MAX_DYNAMIC_LIGHTS:
			light = create_point_light(player, "HeldTorchLight", 1.35, 0.85)
			count += 1
		if light != null:
			light.enabled = held


func _on_weather_changed(raining: bool, intensity: float) -> void:
	_rain_intensity = intensity if raining else 0.0

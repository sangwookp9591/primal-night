class_name Campfire
extends Node2D

## 모닥불. 연료가 떨어지면 꺼진다 (단순 타이머).
## light_radius 는 T4 의 랩터가 회피 판단에 쓴다.
## 타는 동안에만 _process 를 켠다 (성능문서 6.1).

const DEFAULT_CONFIG: CampfireConfig = preload("res://data/props/campfire_config.tres")
const STATE_SHEET: Texture2D = preload("res://assets/sprites/props/campfire_states_sheet.png")
const CELL_SIZE := Vector2(128.0, 128.0)
const FUEL_ADD_SECONDS: float = 90.0
const SMOKE_LURE_RADIUS: float = 480.0

@export var config: CampfireConfig = DEFAULT_CONFIG

var is_lit: bool = false
var fuel_remaining: float = 0.0
var smoky: bool = false
var charcoal_available: bool = false

var _event_bus: Node = null
var _registry: Node = null
var _warm_light: PointLight2D
var _spark_particles: CPUParticles2D
var _smoke_particles: CPUParticles2D
var _ember_particles: CPUParticles2D

func _ready() -> void:
	add_to_group(&"campfire")
	_configure_visual()
	_warm_light = AtmosphereController.create_point_light(self, "WarmLight", 2.35, 1.15)
	_warm_light.enabled = is_lit
	_configure_particles()
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	if has_node("/root/CampfireRegistry"):
		_registry = get_node("/root/CampfireRegistry")
	set_process(false)


func _configure_particles() -> void:
	_spark_particles = ParticleFactory.add_particles(self, &"SparkParticles", 18, 0.8,
		ParticleFactory.make_soft_texture(Color(1.0, 0.55, 0.12, 0.92)))
	ParticleFactory.set_plume(_spark_particles, Vector2(0.0, -17.0), Vector2.UP, 24.0,
		Vector2(25.0, 55.0), Vector2(0.22, 0.5), Vector2(0.0, -12.0))

	_smoke_particles = ParticleFactory.add_particles(self, &"SmokeParticles", 12, 2.1,
		ParticleFactory.make_soft_texture(Color(0.34, 0.37, 0.32, 0.26)))
	ParticleFactory.set_plume(_smoke_particles, Vector2(0.0, -22.0), Vector2.UP, 18.0,
		Vector2(9.0, 18.0), Vector2(0.8, 1.7), Vector2(-2.0, -4.0))

	_ember_particles = ParticleFactory.add_particles(self, &"EmberParticles", 8, 0.48,
		ParticleFactory.make_soft_texture(Color(1.0, 0.28, 0.04, 0.82)))
	_ember_particles.position = Vector2(0.0, -8.0)
	_ember_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_ember_particles.emission_rect_extents = Vector2(12.0, 4.0)
	_ember_particles.scale_amount_min = 0.35
	_ember_particles.scale_amount_max = 0.75
	_set_particles_emitting(is_lit)


func _set_particles_emitting(value: bool) -> void:
	for particles: CPUParticles2D in [_spark_particles, _smoke_particles, _ember_particles]:
		if particles != null:
			particles.emitting = value

func _configure_visual() -> void:
	var sprite := get_node_or_null("CampfireSprite") as AnimatedSprite2D
	if sprite == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"unlit")
	frames.add_frame(&"unlit", _frame_texture(0))
	frames.add_animation(&"lit")
	frames.set_animation_loop(&"lit", true)
	frames.set_animation_speed(&"lit", 6.0)
	for index: int in range(1, 4):
		frames.add_frame(&"lit", _frame_texture(index))
	sprite.sprite_frames = frames
	sprite.play(&"lit" if is_lit else &"unlit")

static func _frame_texture(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = STATE_SHEET
	atlas.region = Rect2(Vector2(index * CELL_SIZE.x, 0.0), CELL_SIZE)
	return atlas

func _process(delta: float) -> void:
	if not is_lit:
		return

	fuel_remaining = maxf(fuel_remaining - delta, 0.0)
	if fuel_remaining <= 0.0:
		extinguish(true)

func light() -> void:
	if is_lit:
		return

	is_lit = true
	if _warm_light != null:
		_warm_light.enabled = true
	_set_particles_emitting(true)
	charcoal_available = false
	fuel_remaining = config.fuel_seconds
	var sprite := get_node_or_null("CampfireSprite") as AnimatedSprite2D
	if sprite != null:
		sprite.play(&"lit")
	# 연료 소진 타이머는 호스트 소유 (설계서 7.2). 클라이언트 복제본은 타이머를
	# 돌리지 않고 NetCampfire 의 소등 복제만 받는다 (W2-T5).
	set_process(multiplayer.is_server())
	if _registry != null and multiplayer.is_server():
		_registry.register_fire(self, global_position, config.light_radius)
	# campfire_lit/extinguished 는 호스트에서만 발신한다 — 클라이언트 복제본도
	# 발신하면 랩터(호스트 소유 AI)가 불을 2개로 인식한다 (tests/props/test_net_campfire.gd).
	if _event_bus != null and multiplayer.is_server():
		_event_bus.campfire_lit.emit(self, global_position, config.light_radius)

func extinguish(fuel_exhausted: bool = false) -> void:
	if not is_lit:
		return

	is_lit = false
	if _warm_light != null:
		_warm_light.enabled = false
	_set_particles_emitting(false)
	charcoal_available = fuel_exhausted
	set_smoky(false)
	fuel_remaining = 0.0
	var sprite := get_node_or_null("CampfireSprite") as AnimatedSprite2D
	if sprite != null:
		sprite.play(&"unlit")
	set_process(false)
	if _registry != null:
		_registry.unregister_fire(self)
	if _event_bus != null and multiplayer.is_server():
		_event_bus.campfire_extinguished.emit(self)

func get_radius() -> float:
	return config.light_radius


func add_fuel(wet: bool) -> bool:
	if not is_lit:
		return false
	fuel_remaining += FUEL_ADD_SECONDS
	set_smoky(wet)
	if wet and _event_bus != null and multiplayer.is_server():
		_event_bus.noise_emitted.emit(global_position, SMOKE_LURE_RADIUS, self)
	return true


func collect_charcoal() -> bool:
	if is_lit or not charcoal_available:
		return false
	charcoal_available = false
	return true


func set_smoky(value: bool) -> void:
	smoky = value and is_lit
	var smoke := get_node_or_null("SmokeColumn") as CanvasItem
	if smoke != null:
		smoke.visible = smoky
	if _smoke_particles != null:
		# 젖은 장작은 연기 기둥이 굵고 오래 남지만 전체 상한은 28개다.
		_smoke_particles.amount = 28 if smoky else 12
		_smoke_particles.lifetime = 3.0 if smoky else 2.1


func _exit_tree() -> void:
	if _registry != null:
		_registry.unregister_fire(self)

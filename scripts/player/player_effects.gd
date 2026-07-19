class_name PlayerEffects
extends Node2D

const HITSTOP_SECONDS: float = 0.04
const MAX_DUST_PARTICLES: int = 12

var _player: Player
var _dust: CPUParticles2D
var _melee_impact: CPUParticles2D
var _arrow_debris: CPUParticles2D
var _event_bus: Node


func _ready() -> void:
	_player = get_parent() as Player
	_create_particles()
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus != null:
		_event_bus.damage_taken.connect(_on_damage_taken)


func _process(_delta: float) -> void:
	if _player == null:
		return
	# 걷기/은신에는 먼지를 내지 않는다. 달리며 실제로 이동할 때만 발밑에 짧게 남긴다.
	_dust.emitting = _player.stance == Player.Stance.RUN \
		and _player.velocity.length_squared() > 16.0


func _create_particles() -> void:
	var dust_texture := ParticleFactory.make_soft_texture(
		Color(0.73, 0.65, 0.46, 0.34))
	_dust = ParticleFactory.add_particles(self, &"FootDust", MAX_DUST_PARTICLES, 0.38,
		dust_texture)
	_dust.position = Vector2(0.0, -1.0)
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(8.0, 2.0)
	_dust.direction = Vector2(0.0, -1.0)
	_dust.spread = 70.0
	_dust.initial_velocity_min = 8.0
	_dust.initial_velocity_max = 18.0
	_dust.gravity = Vector2(0.0, 12.0)
	_dust.scale_amount_min = 0.35
	_dust.scale_amount_max = 0.8

	_melee_impact = ParticleFactory.add_particles(self, &"MeleeImpact", 10, 0.18,
		ParticleFactory.make_soft_texture(Color(1.0, 0.78, 0.34, 0.85)))
	ParticleFactory.set_burst(_melee_impact, Vector2.RIGHT, 180.0, Vector2(30.0, 70.0),
		Vector2(0.0, 45.0), Vector2(0.25, 0.65))

	_arrow_debris = ParticleFactory.add_particles(self, &"ArrowDebris", 8, 0.25,
		ParticleFactory.make_soft_texture(Color(0.68, 0.53, 0.31, 0.88)))
	ParticleFactory.set_burst(_arrow_debris, Vector2.RIGHT, 160.0, Vector2(22.0, 55.0),
		Vector2(0.0, 70.0), Vector2(0.25, 0.55))


func play_impact(kind: StringName, at: Vector2 = Vector2.ZERO) -> void:
	var effect := _arrow_debris if kind == &"arrow" else _melee_impact
	effect.global_position = at if at != Vector2.ZERO else global_position
	effect.restart()
	if kind != &"arrow":
		_play_visual_hitstop()


func _on_damage_taken(target: Node, _amount: float, kind: StringName) -> void:
	if target is Node2D and target != _player:
		play_impact(kind, (target as Node2D).global_position)


func _play_visual_hitstop() -> void:
	var body := _player.get_node_or_null("VisualRig/BaseBody") as AnimatedSprite2D
	if body == null:
		return
	body.speed_scale = 0.0
	await get_tree().create_timer(HITSTOP_SECONDS).timeout
	if is_instance_valid(body):
		body.speed_scale = 1.0


class_name AmbientParticles
extends Node2D

const MAX_DAY_MOTES: int = 28
const MAX_FIREFLIES: int = 12

@export var clock_path: NodePath = ^"../SessionClock"
@export var player_path: NodePath = ^"../Player"

var _clock: SessionClock
var _player: Node2D
var _day_motes: CPUParticles2D
var _fireflies: CPUParticles2D


func _ready() -> void:
	_clock = get_node(clock_path) as SessionClock
	_player = get_node_or_null(player_path) as Node2D
	_create_particles()
	_clock.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(_clock.current_phase)


func _process(_delta: float) -> void:
	if _player != null:
		global_position = _player.global_position


func _create_particles() -> void:
	_day_motes = ParticleFactory.add_particles(self, &"DayMotes", MAX_DAY_MOTES, 5.5,
		ParticleFactory.make_soft_texture(Color(1.0, 0.91, 0.58, 0.28)))
	_configure_ambient(_day_motes, Vector2(5.0, -3.0), Vector2(0.18, 0.42))
	_fireflies = ParticleFactory.add_particles(self, &"NightFireflies", MAX_FIREFLIES, 4.2,
		ParticleFactory.make_soft_texture(Color(0.72, 1.0, 0.38, 0.78)))
	_configure_ambient(_fireflies, Vector2(2.0, -5.0), Vector2(0.3, 0.65))


func _configure_ambient(particles: CPUParticles2D, drift: Vector2,
		scale_range: Vector2) -> void:
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(235.0, 145.0)
	particles.direction = drift.normalized()
	particles.spread = 80.0
	particles.initial_velocity_min = drift.length() * 0.45
	particles.initial_velocity_max = drift.length()
	particles.scale_amount_min = scale_range.x
	particles.scale_amount_max = scale_range.y


func _on_phase_changed(phase: SessionClock.Phase) -> void:
	var is_night := phase == SessionClock.Phase.NIGHT
	_day_motes.emitting = not is_night
	_fireflies.emitting = is_night


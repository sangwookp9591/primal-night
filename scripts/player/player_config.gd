class_name PlayerConfig
extends Resource

const DEFAULT_WALK_NOISE: NoiseProfile = preload("res://data/senses/noise_walk.tres")
const DEFAULT_RUN_NOISE: NoiseProfile = preload("res://data/senses/noise_run.tres")

@export var walk_speed: float = 150.0
@export var run_speed: float = 240.0
@export var walk_noise_profile: NoiseProfile = DEFAULT_WALK_NOISE
@export var run_noise_profile: NoiseProfile = DEFAULT_RUN_NOISE
@export var base_walk_noise: float = 80.0
@export var base_run_noise: float = 160.0
@export var noise_emit_interval: float = 0.25

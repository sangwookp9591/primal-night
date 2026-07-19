class_name PlayerConfig
extends Resource

const DEFAULT_WALK_NOISE: NoiseProfile = preload("res://data/senses/noise_walk.tres")
const DEFAULT_RUN_NOISE: NoiseProfile = preload("res://data/senses/noise_run.tres")
const DEFAULT_CROUCH_NOISE: NoiseProfile = preload("res://data/senses/noise_sneak.tres")
const DEFAULT_BUSH_RUN_NOISE: NoiseProfile = preload("res://data/senses/noise_bush_run.tres")

@export var walk_speed: float = 115.0
@export var run_speed: float = 185.0
@export var crouch_speed: float = 70.0
@export var walk_noise_profile: NoiseProfile = DEFAULT_WALK_NOISE
@export var run_noise_profile: NoiseProfile = DEFAULT_RUN_NOISE
## 웅크리면 어디서든 이 프로필로 조용해진다 (설계서 5.6).
@export var crouch_noise_profile: NoiseProfile = DEFAULT_CROUCH_NOISE
## 수풀 안에서 달리면 이 프로필로 바뀐다 — 수풀을 헤치는 소리는 평소 달리기보다 크다.
@export var bush_run_noise_profile: NoiseProfile = DEFAULT_BUSH_RUN_NOISE
@export var noise_emit_interval: float = 0.25

class_name Player
extends CharacterBody2D

const DEFAULT_CONFIG: PlayerConfig = preload("res://resources/player/player_config.tres")

@export var config: PlayerConfig = DEFAULT_CONFIG

## 생존 규칙은 컴포넌트가 소유한다. Player 는 입력과 이동만 안다 (설계서 9.2).
@onready var health: HealthComponent = $HealthComponent
@onready var stamina: StaminaComponent = $StaminaComponent

## 치료 중에는 양쪽 모두 이동이 제한된다 (설계서 5.2).
var movement_locked: bool = false

var _noise_radius: float = 0.0
var _noise_emit_elapsed: float = 0.0
var _event_bus: Node = null

func _ready() -> void:
	add_to_group("player")
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")

func _physics_process(delta: float) -> void:
	var input_vector: Vector2 = Vector2.ZERO if movement_locked else _get_input_vector()
	var moving: bool = not input_vector.is_zero_approx()
	# 스태미나가 없으면 run 을 누르고 있어도 달릴 수 없다.
	var running: bool = moving and Input.is_action_pressed("run") and stamina.can_run()
	var speed: float = config.run_speed if running else config.walk_speed

	stamina.update(running, moving, delta)

	velocity = input_vector * speed
	move_and_slide()

	if not moving:
		_noise_radius = 0.0
		_noise_emit_elapsed = 0.0
		return

	_noise_radius = config.base_run_noise if running else config.base_walk_noise
	_noise_emit_elapsed += delta
	if _noise_emit_elapsed >= config.noise_emit_interval:
		_noise_emit_elapsed = 0.0
		if _event_bus != null:
			_event_bus.emit_signal("noise_emitted", global_position, _noise_radius, self)

func get_noise_radius() -> float:
	return _noise_radius

func _get_input_vector() -> Vector2:
	var horizontal: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vertical: float = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var raw: Vector2 = Vector2(horizontal, vertical)
	if raw.is_zero_approx():
		return Vector2.ZERO

	var iso: Vector2 = Vector2(raw.x - raw.y, (raw.x + raw.y) * 0.5)
	return iso.normalized()

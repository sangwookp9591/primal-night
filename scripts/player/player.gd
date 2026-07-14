class_name Player
extends CharacterBody2D

const DEFAULT_CONFIG: PlayerConfig = preload("res://resources/player/player_config.tres")

@export var config: PlayerConfig = DEFAULT_CONFIG

## 생존 규칙은 컴포넌트가 소유한다. Player 는 입력과 이동만 안다 (설계서 9.2).
@onready var health: HealthComponent = $HealthComponent
@onready var stamina: StaminaComponent = $StaminaComponent
@onready var inventory: Inventory = $Inventory
@onready var interactor: Interactor = $Interactor
## 체온·수분·포만·피로 (설계서 5.1). 코드로 붙인다 — 수치가 하나 늘 때마다
## player.tscn 을 고치지 않는다. 시뮬은 이 노드가 호스트에서만 스스로 돌린다.
var stats: SurvivalStats = SurvivalStats.new()

## 치료 중에는 양쪽 모두 이동이 제한된다 (설계서 5.2).
var movement_locked: bool = false

## StealthZone(수풀)이 겹침으로 직접 설정한다 (설계서 5.6). Player 는 트리를 뒤지지 않는다.
var in_bush: bool = false

## 이 아바타를 조종하는 peer id. 로컬 기계가 조종하지 않는 원격 아바타는
## 입력을 읽지 않는다 — 위치는 호스트 검증(NetMovement)과 스냅샷이 정한다 (설계서 7.2).
## 싱글플레이는 offline peer id(1) == 기본값이라 기존 흐름 그대로다 (설계서 9.3).
var controller_peer_id: int = 1

var _noise_radius: float = 0.0
var _noise_emit_elapsed: float = 0.0
var _noise_seconds: float = 0.0
var _event_bus: Node = null
var _noise_emitter: NoiseEmitter = NoiseEmitter.new()

func _ready() -> void:
	add_to_group("player")
	stats.name = "SurvivalStats"
	stats.config = health.config
	add_child(stats)
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")

func _physics_process(delta: float) -> void:
	_noise_seconds += delta
	if controller_peer_id != multiplayer.get_unique_id():
		return
	var input_vector: Vector2 = Vector2.ZERO if movement_locked else _get_input_vector()
	var moving: bool = not input_vector.is_zero_approx()
	var crouching: bool = Input.is_action_pressed("crouch")
	# 스태미나가 없으면 run 을 누르고 있어도 달릴 수 없다. 웅크리면 달리지 않는다 (은신 우선).
	var running: bool = moving and not crouching and Input.is_action_pressed("run") and stamina.can_run()
	var speed: float = config.crouch_speed if crouching else (config.run_speed if running else config.walk_speed)

	stamina.update(running, moving, delta, stats.fatigue_ratio())

	velocity = input_vector * speed
	move_and_slide()

	if not moving:
		_noise_radius = 0.0
		_noise_emit_elapsed = 0.0
		return

	var profile: NoiseProfile = _select_noise_profile(crouching, running)
	_noise_radius = _select_noise_radius(crouching, running)
	_noise_emit_elapsed += delta
	if _noise_emit_elapsed >= config.noise_emit_interval:
		_noise_emit_elapsed = 0.0
		if _event_bus != null:
			_noise_emitter.emit_profile(_event_bus, profile, global_position, self, _noise_seconds)

func get_noise_radius() -> float:
	return _noise_radius

## 수풀에서 달리면 헤치는 소리가 우선한다. 그다음은 웅크림(항상 조용), 그다음 걷기/달리기.
func _select_noise_profile(crouching: bool, running: bool) -> NoiseProfile:
	if in_bush and running:
		return config.bush_run_noise_profile
	if crouching:
		return config.crouch_noise_profile
	return config.run_noise_profile if running else config.walk_noise_profile

func _select_noise_radius(crouching: bool, running: bool) -> float:
	if in_bush and running:
		return config.base_bush_run_noise
	if crouching:
		return config.base_crouch_noise
	return config.base_run_noise if running else config.base_walk_noise

func _get_input_vector() -> Vector2:
	var horizontal: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vertical: float = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var raw: Vector2 = Vector2(horizontal, vertical)
	if raw.is_zero_approx():
		return Vector2.ZERO

	var iso: Vector2 = Vector2(raw.x - raw.y, (raw.x + raw.y) * 0.5)
	return iso.normalized()

class_name Player
extends CharacterBody2D

const DEFAULT_CONFIG: PlayerConfig = preload("res://resources/player/player_config.tres")

## 이동 자세 — 소음 프로필 선택과 호스트 교차검증의 공통 어휘 (설계서 5.6/7.4).
## 세기 순서: CROUCH < WALK < RUN. NetMovement 가 이 순서로 위조 주장을 강등한다.
enum Stance { WALK, RUN, CROUCH }

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

## 로컬 컨트롤러가 이번 틱에 고른 자세. NetMovement 가 이 값을 읽어 이동 의도에 실어
## 호스트로 보낸다 (원격 아바타는 이 필드를 직접 쓰지 않는다 — 자기 브랜치 입력만 반영).
var stance: int = Stance.WALK

## 호스트가 교차검증 후 확정한 자세 (설계서 7.4). 원격 아바타의 소음 판정은 클라이언트
## 주장이 아니라 이 값을 쓴다 (SmellGrid._emit_remote_player_noise). 로컬 아바타 자신의
## 소음은 이 필드를 거치지 않고 stance 를 바로 쓴다 — 자기 이동은 호스트에서 그대로 신뢰.
var last_validated_stance: int = Stance.WALK

## 이 아바타를 조종하는 peer id. 로컬 기계가 조종하지 않는 원격 아바타는
## 입력을 읽지 않는다 — 위치는 호스트 검증(NetMovement)과 스냅샷이 정한다 (설계서 7.2).
## 싱글플레이는 offline peer id(1) == 기본값이라 기존 흐름 그대로다 (설계서 9.3).
var controller_peer_id: int = 1

var _noise_radius: float = 0.0
var _noise_emit_elapsed: float = 0.0
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
	if controller_peer_id != multiplayer.get_unique_id():
		return
	var input_vector: Vector2 = Vector2.ZERO if movement_locked else _get_input_vector()
	var moving: bool = not input_vector.is_zero_approx()
	var crouching: bool = Input.is_action_pressed("crouch")
	# 스태미나가 없으면 run 을 누르고 있어도 달릴 수 없다. 웅크리면 달리지 않는다 (은신 우선).
	var running: bool = moving and not crouching and Input.is_action_pressed("run") and stamina.can_run()
	stance = Stance.CROUCH if crouching else (Stance.RUN if running else Stance.WALK)
	var speed: float = config.crouch_speed if crouching else (config.run_speed if running else config.walk_speed)

	stamina.update(running, moving, delta, stats.fatigue_ratio())

	velocity = input_vector * speed
	move_and_slide()

	if not moving:
		_noise_radius = 0.0
		_noise_emit_elapsed = 0.0
		return

	var profile: NoiseProfile = get_noise_profile_for_stance(stance)
	_noise_radius = profile.radius
	_noise_emit_elapsed += delta
	if _noise_emit_elapsed >= config.noise_emit_interval:
		_noise_emit_elapsed = 0.0
		if _event_bus != null:
			_noise_emitter.emit_profile(_event_bus, profile, global_position, self)

func get_noise_radius() -> float:
	return _noise_radius

## 자세별 소음 프로필. 로컬(자기 입력 기준)과 원격(호스트 검증 자세 기준,
## SmellGrid._emit_remote_player_noise) 이 이 표를 공유해 판정이 갈라지지 않는다.
## 수풀에서 달리면 헤치는 소리가 우선한다. 그다음은 웅크림(항상 조용), 그다음 걷기/달리기.
## 수풀 여부는 자기 상태(in_bush — StealthZone 이 겹침으로 설정)에서 직접 읽는다.
func get_noise_profile_for_stance(for_stance: int) -> NoiseProfile:
	if in_bush and for_stance == Stance.RUN:
		return config.bush_run_noise_profile
	if for_stance == Stance.CROUCH:
		return config.crouch_noise_profile
	return config.run_noise_profile if for_stance == Stance.RUN else config.walk_noise_profile

## 자세별 최대 이동 속도. NetMovement 가 주장된 자세를 실측 속도와 교차검증할 때 쓴다.
func max_speed_for_stance(for_stance: int) -> float:
	match for_stance:
		Stance.CROUCH:
			return config.crouch_speed
		Stance.RUN:
			return config.run_speed
		_:
			return config.walk_speed

func _get_input_vector() -> Vector2:
	var horizontal: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vertical: float = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var raw: Vector2 = Vector2(horizontal, vertical)
	if raw.is_zero_approx():
		return Vector2.ZERO

	var iso: Vector2 = Vector2(raw.x - raw.y, (raw.x + raw.y) * 0.5)
	return iso.normalized()

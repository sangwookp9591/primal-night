class_name Raptor
extends CharacterBody2D

## 랩터 AI (설계서 5.5). 상태: 배회 → 조사 → 추격 → 도주.
## ★ 공정성 규칙 (설계서 5.3): 소리 발신자 노드를 추적하지 않는다.
##   "마지막으로 들린 위치"만 기억해 조사한다.
## 지각·상태 결정은 ai_tick_interval 주기로만 (성능문서 6.3).

enum State { WANDER, INVESTIGATE, CHASE, FLEE }

signal state_changed(previous_state: int, new_state: int)
signal chase_started()

const DEFAULT_DATA: CreatureData = preload("res://data/creatures/raptor.tres")
const STATE_NAMES: Array[StringName] = [&"wander", &"investigate", &"chase", &"flee"]
## 지형 벽 물리 레이어 (test_world Collision 타일 = layer 1).
const TERRAIN_MASK: int = 1

@export var data: CreatureData = DEFAULT_DATA

var state: int = State.WANDER
var move_target: Vector2 = Vector2.ZERO

## 마지막으로 들린 위치 — 좌표만 저장한다. 발신자 노드 저장 금지.
var _last_heard_position: Vector2 = Vector2.ZERO
var _heard_news: bool = false

## 차폐 검사는 physics 프레임 안에서만 가능하므로 이벤트를 보류해 두고 처리한다.
var _pending_noise_position: Vector2 = Vector2.ZERO
var _pending_noise_radius: float = 0.0
var _has_pending_noise: bool = false

var _ai_elapsed: float = 0.0
var _perf: Node = null
## 매 틱 그룹 재검색을 피하기 위한 캐시 (성능문서 6.1).
var _player: Node2D = null
var _smell_grid: SmellGrid = null

func _ready() -> void:
	move_target = global_position
	if has_node("/root/PerfMonitor"):
		_perf = get_node("/root/PerfMonitor")
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").noise_emitted.connect(_on_noise_emitted)

func _physics_process(delta: float) -> void:
	if _has_pending_noise:
		_resolve_pending_noise()

	_ai_elapsed += delta
	if _ai_elapsed >= data.ai_tick_interval:
		_ai_elapsed = 0.0
		if _perf != null:
			_perf.begin_sample(&"ai")
		_ai_tick()
		if _perf != null:
			_perf.end_sample(&"ai")

## 지각과 상태 결정 한 틱. physics 프레임 안에서 호출된다.
## 지각 우선순위: 시야(직접 지각) > 소리 > 냄새.
func _ai_tick() -> void:
	var player: Node2D = _find_player()

	match state:
		State.WANDER, State.INVESTIGATE:
			if _can_see_player(player, data.sight_radius):
				move_target = player.global_position
				_change_state(State.CHASE)
			elif _heard_news:
				move_target = _last_heard_position
				_change_state(State.INVESTIGATE)
			elif _smells_blood():
				move_target = _smell_step_target()
				_change_state(State.INVESTIGATE)
			elif state == State.INVESTIGATE and _arrived_at(move_target):
				# 도착했는데 아무것도 없다 — 대상 상실, 배회 복귀 (설계서 14.1).
				_change_state(State.WANDER)
		State.CHASE:
			if _can_see_player(player, data.lose_sight_radius):
				move_target = player.global_position
			else:
				# 시야 상실: 마지막 목격 위치(move_target)를 조사한다.
				_change_state(State.INVESTIGATE)
	_heard_news = false

func _find_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player

func _can_see_player(player: Node2D, radius: float) -> bool:
	return player != null and global_position.distance_to(player.global_position) <= radius

func _find_smell_grid() -> SmellGrid:
	if _smell_grid == null or not is_instance_valid(_smell_grid):
		_smell_grid = get_tree().get_first_node_in_group(&"smell_grid") as SmellGrid
	return _smell_grid

func _smells_blood() -> bool:
	var grid: SmellGrid = _find_smell_grid()
	return grid != null and grid.get_smell_at(global_position) >= data.smell_threshold

## 냄새 농도가 진해지는 방향으로 한 셀만큼 전진할 지점.
## 발생 좌표를 받지 않는다 — 경사를 거슬러 올라간다 (설계서 5.4).
func _smell_step_target() -> Vector2:
	var grid: SmellGrid = _find_smell_grid()
	var gradient: Vector2 = grid.get_gradient_direction(global_position)
	if gradient == Vector2.ZERO:
		# 자기 셀이 가장 진하다 — 냄새 원점에 도달한 것. 제자리 조사.
		return global_position
	return global_position + gradient * grid.config.cell_size

func _arrived_at(target: Vector2) -> bool:
	return global_position.distance_to(target) <= data.investigate_arrive_distance

func get_state_name() -> StringName:
	return STATE_NAMES[state]

func _change_state(new_state: int) -> void:
	if state == new_state:
		return
	var previous_state: int = state
	state = new_state
	state_changed.emit(previous_state, new_state)
	if new_state == State.CHASE:
		chase_started.emit()

func _on_noise_emitted(position: Vector2, radius: float, source: Node) -> void:
	if source == self:
		return
	# 차폐와 무관하게 반경 밖이면 절대 들리지 않는다 — 즉시 폐기 (성능문서 5.3).
	if global_position.distance_to(position) > radius:
		return
	# 위치와 반경만 보류한다. 발신자 노드는 저장하지 않는다 (공정성 규칙).
	_pending_noise_position = position
	_pending_noise_radius = radius
	_has_pending_noise = true

## 벽 차폐를 반영해 보류된 소리를 확정한다 (설계서 5.3: 벽은 소리를 감쇠한다).
func _resolve_pending_noise() -> void:
	_has_pending_noise = false
	var effective_radius: float = _pending_noise_radius
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		_pending_noise_position, global_position, TERRAIN_MASK)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		effective_radius *= data.occlusion_attenuation
	if global_position.distance_to(_pending_noise_position) > effective_radius:
		return
	_last_heard_position = _pending_noise_position
	_heard_news = true

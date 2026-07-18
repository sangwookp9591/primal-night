class_name Scavenger
extends CharacterBody2D

## 첫날 청소동물 MVP: 냄새 경사를 따라 사체/바닥 먹이에 접근해 보상을 소모하고,
## 플레이어가 가까워지면 싸우지 않고 흩어진다. 모든 판정과 소비는 호스트 권위다.

enum State { FORAGE, EAT, FLEE }

signal state_changed(previous_state: int, new_state: int)
signal food_consumed(food: Node)
signal eating_noise_emitted(position: Vector2)

const DEFAULT_DATA: CreatureData = preload("res://data/creatures/scavenger.tres")
const EATING_NOISE: NoiseProfile = preload("res://data/senses/noise_scavenger_eat.tres")
const SNAPSHOT_INTERVAL_SECONDS: float = 0.2
const CLIENT_INTERPOLATION_SPEED: float = 8.0
const PLAYER_FLEE_RADIUS: float = 120.0
const FOOD_REACH_RADIUS: float = 28.0
const SMELL_STEP_DISTANCE: float = 96.0

@export var data: CreatureData = DEFAULT_DATA
@export var eat_interval_seconds: float = 2.0

var state: int = State.FORAGE
var move_target: Vector2
var _replicated_position: Vector2
var _ai_elapsed: float = 0.0
var _snapshot_elapsed: float = 0.0
var _eat_elapsed: float = 0.0
var _eat_time_multiplier: float = 1.0
var _smell_grid: SmellGrid
var _nav_agent: NavigationAgent2D
var _food_target: Node2D
var _noise_emitter := NoiseEmitter.new()

func _ready() -> void:
	add_to_group(&"scavenger")
	move_target = global_position
	_replicated_position = global_position
	_nav_agent = get_node_or_null(^"NavigationAgent2D")
	_smell_grid = SmellGrid.find_in(get_tree())

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		global_position = global_position.lerp(_replicated_position,
			clampf(delta * CLIENT_INTERPOLATION_SPEED, 0.0, 1.0))
		return
	_ai_elapsed += delta
	if _ai_elapsed >= data.ai_tick_interval:
		_ai_elapsed = 0.0
		_ai_tick()
	if state == State.EAT:
		_eat_elapsed += delta
		if _eat_elapsed >= eat_interval_seconds * _eat_time_multiplier:
			_eat_elapsed = 0.0
			_consume_food()
	_move_along_path()
	_snapshot_elapsed += delta
	if _snapshot_elapsed >= SNAPSHOT_INTERVAL_SECONDS:
		_snapshot_elapsed = 0.0
		if multiplayer.get_peers().size() > 0:
			apply_scavenger_snapshot.rpc(global_position, state, move_target)

func _ai_tick() -> void:
	var player := _nearest_player(PLAYER_FLEE_RADIUS)
	if player != null:
		var away := global_position - player.global_position
		if away.is_zero_approx():
			away = Vector2.RIGHT
		move_target = global_position + away.normalized() * data.wander_range
		_food_target = null
		_change_state(State.FLEE)
		return
	if state == State.FLEE:
		_change_state(State.FORAGE)
	_food_target = _nearest_edible()
	if _food_target != null:
		move_target = _food_target.global_position
		_change_state(State.EAT if global_position.distance_to(move_target) <= FOOD_REACH_RADIUS else State.FORAGE)
		return
	if _smell_grid == null:
		_smell_grid = SmellGrid.find_in(get_tree())
	if _smell_grid != null and _smell_grid.get_smell_at(global_position) >= data.smell_threshold:
		var gradient := _smell_grid.get_gradient_direction(global_position)
		if not gradient.is_zero_approx():
			move_target = global_position + gradient * SMELL_STEP_DISTANCE

func _nearest_player(radius: float) -> Node2D:
	var nearest: Node2D
	var best := radius * radius
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node2D
		if player == null or player.multiplayer != multiplayer:
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance <= best:
			best = distance
			nearest = player
	return nearest

func _nearest_edible() -> Node2D:
	var nearest: Node2D
	var best := data.lose_sight_radius * data.lose_sight_radius
	for group: StringName in [&"carcass", &"world_item"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var food := node as Node2D
			if food == null or food.multiplayer != multiplayer or not _is_edible(food):
				continue
			var distance := global_position.distance_squared_to(food.global_position)
			if distance < best:
				best = distance
				nearest = food
	return nearest

func _is_edible(food: Node2D) -> bool:
	if food is Carcass:
		return not (food as Carcass).is_fully_butchered()
	if food is WorldItem:
		var world_item := food as WorldItem
		var item: ItemData = get_node("/root/GameData").get_item(world_item.item_id)
		return world_item.count > 0 and item != null and item.is_smell_source()
	return false

func _consume_food() -> void:
	if _food_target == null or not is_instance_valid(_food_target) \
			or global_position.distance_to(_food_target.global_position) > FOOD_REACH_RADIUS:
		_change_state(State.FORAGE)
		return
	var consumed := false
	if _food_target is Carcass:
		consumed = (_food_target as Carcass).consume_stage_by_scavenger()
	elif _food_target is WorldItem:
		consumed = (_food_target as WorldItem).consume_one_by_scavenger()
	if not consumed:
		_food_target = null
		_change_state(State.FORAGE)
		return
	var eaten := _food_target
	if has_node("/root/EventBus"):
		_noise_emitter.emit_profile(get_node("/root/EventBus"), EATING_NOISE, global_position, self)
	eating_noise_emitted.emit(global_position)
	food_consumed.emit(eaten)

func _move_along_path() -> void:
	if state == State.EAT:
		velocity = Vector2.ZERO
		return
	if _nav_agent == null:
		var direct := move_target - global_position
		velocity = direct.normalized() * data.walk_speed if not direct.is_zero_approx() else Vector2.ZERO
		global_position += velocity * get_physics_process_delta_time()
		return
	if _nav_agent.target_position != move_target:
		_nav_agent.target_position = move_target
	if _nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	var direction := _nav_agent.get_next_path_position() - global_position
	velocity = direction.normalized() * data.walk_speed if not direction.is_zero_approx() else Vector2.ZERO
	move_and_slide()

func _change_state(next: int) -> void:
	if state == next:
		return
	var previous := state
	state = next
	if state != State.EAT:
		_eat_elapsed = 0.0
	state_changed.emit(previous, state)

func apply_difficulty(config: DifficultyConfig) -> void:
	# 기존 자원 여유 축만 재사용: gentle 1.5 => 먹는 간격 1.5배.
	_eat_time_multiplier = maxf(config.resource_spawn_quantity_multiplier, 0.25)

func eating_interval() -> float:
	return eat_interval_seconds * _eat_time_multiplier

@rpc("authority", "call_remote", "unreliable")
func apply_scavenger_snapshot(position: Vector2, next_state: int, target: Vector2) -> void:
	if is_multiplayer_authority() or not position.is_finite() or not target.is_finite() \
			or next_state < State.FORAGE or next_state > State.FLEE:
		return
	_replicated_position = position
	state = next_state
	move_target = target

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
const SNAPSHOT_INTERVAL_SECONDS: float = 0.2
const CLIENT_INTERPOLATION_SPEED: float = 8.0

@export var data: CreatureData = DEFAULT_DATA

var state: int = State.WANDER
var move_target: Vector2 = Vector2.ZERO

## 마지막으로 들린 위치 — 좌표만 저장한다. 발신자 노드 저장 금지.
var _last_heard_position: Vector2 = Vector2.ZERO
var _heard_news: bool = false
## 이번에 들린 소리의 세기 = 차폐를 반영한 유효 반경 (px). 관심도 비교용.
var _heard_interest: float = 0.0

## 관심도 (설계서 14.1): 지금 쫓는 단서의 세기와 감각 종류.
## 같은 감각의 더 강한 단서만 목표를 갈아탄다 — 작은 소리가 큰 소리를 흔들지 못한다.
## 감각끼리는 세기를 비교하지 않는다 (반경 px 와 냄새 농도는 단위가 다르다).
## 감각 사이 우선순위는 _ai_tick 의 분기 순서(시야 > 소리 > 냄새)가 이미 정한다.
var _interest: float = 0.0
var _interest_kind: StringName = &""
## 조사 원점과 남은 훑기 횟수. 훑기 목표는 이 원점 + rng 에서만 나온다 —
## 플레이어 좌표는 절대 섞이지 않는다 (공정성 규칙, W1 뮤테이션 M3).
var _search_origin: Vector2 = Vector2.ZERO
var _sweeps_left: int = 0

## 차폐 검사는 physics 프레임 안에서만 가능하므로 이벤트를 보류해 두고 처리한다.
var _pending_noise_position: Vector2 = Vector2.ZERO
var _pending_noise_radius: float = 0.0
var _has_pending_noise: bool = false

## 켜진 모닥불 목록: [{node, position, radius}] (campfire_lit 로 등록·해제).
var _campfires: Array[Dictionary] = []

var _ai_elapsed: float = 0.0
var _snapshot_elapsed: float = 0.0
var _replicated_position: Vector2 = Vector2.ZERO
var _perf: Node = null
var _smell_grid: SmellGrid = null
var _pack_coordinator: Node = null
var _nav_agent: NavigationAgent2D = null
var _sprite_animator: Node = null
var _alert_label: Label = null
var _alert_remaining: float = 0.0

## 배회 목표 선택용. 테스트는 seed 를 고정해 결정적으로 만든다.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 디버그 시각화 (설계서 13장): 상태, 감지 반경, 목표 지점, 경로.
var debug_enabled: bool = false

func _ready() -> void:
	add_to_group(&"raptor")
	move_target = global_position
	_replicated_position = global_position
	rng.randomize()
	_nav_agent = get_node_or_null(^"NavigationAgent2D")
	_sprite_animator = get_node_or_null(^"SpriteAnimator")
	_alert_label = get_node_or_null(^"AlertLabel")
	if has_node("/root/PerfMonitor"):
		_perf = get_node("/root/PerfMonitor")
	if has_node("/root/EventBus"):
		var event_bus: Node = get_node("/root/EventBus")
		event_bus.noise_emitted.connect(_on_noise_emitted)
		event_bus.campfire_lit.connect(_on_campfire_lit)
		event_bus.campfire_extinguished.connect(_on_campfire_extinguished)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		var visual_velocity: Vector2 = _replicated_position - global_position
		global_position = global_position.lerp(_replicated_position,
			clampf(delta * CLIENT_INTERPOLATION_SPEED, 0.0, 1.0))
		_refresh_visual_animation(visual_velocity)
		_tick_alert(delta)
		if debug_enabled:
			queue_redraw()
		return

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

	_tick_alert(delta)

	_move_along_path()
	_refresh_visual_animation(velocity)
	_snapshot_elapsed += delta
	if _snapshot_elapsed >= SNAPSHOT_INTERVAL_SECONDS:
		_snapshot_elapsed = 0.0
		if multiplayer.get_peers().size() > 0:
			apply_raptor_snapshot.rpc(global_position, state, move_target)

	if debug_enabled:
		queue_redraw()

func _tick_alert(delta: float) -> void:
	if _alert_remaining <= 0.0:
		return
	_alert_remaining -= delta
	if _alert_remaining <= 0.0 and _alert_label != null:
		_alert_label.visible = false


func _refresh_visual_animation(visual_velocity: Vector2) -> void:
	if _sprite_animator != null and _sprite_animator.has_method("update_from_velocity"):
		_sprite_animator.update_from_velocity(visual_velocity, state)

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F4:
		debug_enabled = not debug_enabled
		queue_redraw()

func _draw() -> void:
	if not debug_enabled:
		return
	var state_color: Color = [Color.GRAY, Color.YELLOW, Color.RED, Color.DODGER_BLUE][state]
	# 감지 반경 (진입/이탈).
	draw_arc(Vector2.ZERO, data.sight_radius, 0.0, TAU, 48, Color(state_color, 0.5), 1.5)
	draw_arc(Vector2.ZERO, data.lose_sight_radius, 0.0, TAU, 48, Color(state_color, 0.2), 1.0)
	# 현재 상태 이름.
	draw_string(ThemeDB.fallback_font, Vector2(-24.0, -84.0), String(get_state_name()),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, state_color)
	# 이동 목표 (조사 지점 / 추격 대상 / 도주 지점) X 마커.
	var target_local: Vector2 = to_local(move_target)
	draw_line(target_local + Vector2(-8.0, -8.0), target_local + Vector2(8.0, 8.0), state_color, 2.0)
	draw_line(target_local + Vector2(-8.0, 8.0), target_local + Vector2(8.0, -8.0), state_color, 2.0)
	# 마지막으로 들린 위치.
	if _heard_news:
		draw_circle(to_local(_last_heard_position), 6.0, Color.ORANGE)
	# 현재 내비게이션 경로.
	if _nav_agent != null:
		var path: PackedVector2Array = _nav_agent.get_current_navigation_path()
		for path_index: int in range(path.size() - 1):
			draw_line(to_local(path[path_index]), to_local(path[path_index + 1]),
				Color(state_color, 0.6), 1.0)

## NavigationAgent2D 를 따라 move_target 으로 이동한다.
## 경로 재계산은 목표가 실제로 바뀐 프레임에만 일어난다 (매 프레임 재계산 금지).
func _move_along_path() -> void:
	if _nav_agent == null:
		return
	if _nav_agent.target_position != move_target:
		_nav_agent.target_position = move_target
	if _nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	var next_position: Vector2 = _nav_agent.get_next_path_position()
	var direction: Vector2 = next_position - global_position
	if direction.is_zero_approx():
		velocity = Vector2.ZERO
		return
	var speed: float = data.chase_speed if state == State.CHASE else data.walk_speed
	velocity = direction.normalized() * speed
	move_and_slide()

## 지각과 상태 결정 한 틱. physics 프레임 안에서 호출된다.
## 지각 우선순위: 시야(직접 지각) > 소리 > 냄새.
## 2인 협동: 플레이어 전원을 지각한다 — 가장 가까운 비보호 플레이어를 추격하고,
## 보이는 전원이 불 곁일 때만 물러난다 (W2-T5, tests/creature/test_raptor_two_players.gd).
func _ai_tick() -> void:
	match state:
		State.WANDER, State.INVESTIGATE:
			if _fire_index_containing(global_position, data.fire_exit_ratio) >= 0:
				# 불이 막 켜져 반경 안에 갇혔다 — 즉시 물러난다.
				_start_flee()
			else:
				var seen: Dictionary = _perceive_players(data.sight_radius)
				var target: Node2D = seen.nearest_unprotected
				if target != null:
					move_target = target.global_position
					_change_state(State.CHASE)
				elif _heard_news and _is_more_interesting(&"noise", _heard_interest):
					_adopt_cue(&"noise", _heard_interest, _last_heard_position)
				else:
					var smell: float = _smell_strength()
					if smell >= data.smell_threshold and _is_more_interesting(&"smell", smell):
						_adopt_cue(&"smell", smell, _smell_step_target())
					elif state == State.INVESTIGATE and _arrived_at(move_target):
						# 도착했는데 아무것도 없다 — 즉시 포기하지 않고 주변을 훑는다 (설계서 14.1).
						_continue_search()
					elif state == State.WANDER and _arrived_at(move_target):
						_pick_wander_target()
		State.CHASE:
			if _fire_index_containing(global_position, 1.0) >= 0:
				_start_flee()
			else:
				var seen: Dictionary = _perceive_players(data.lose_sight_radius)
				var target: Node2D = seen.nearest_unprotected
				if target != null:
					# 가장 가까운 비보호 플레이어를 추격한다 — 대상이 불 곁에 숨으면
					# 노출된 동료로 전환한다 (한 명만 보호될 때 물러나지 않는다).
					move_target = target.global_position
				elif seen.any_visible:
					# 보이는 플레이어 전원이 불 곁이다 — 추격 포기 (목표 장면의 결말).
					_start_flee()
				else:
					# 시야 상실: 마지막 목격 위치(move_target)를 조사하고 그 주변을 훑는다.
					# 세기 0 으로 둔다 — 어떤 소리·냄새든 이 조사를 갈아탈 수 있다.
					_adopt_cue(&"sight", 0.0, move_target)
		State.FLEE:
			var fire_index: int = _fire_index_containing(global_position, data.fire_exit_ratio)
			if fire_index < 0:
				# 이탈 반경 밖 — 히스테리시스 해제, 배회 복귀.
				_change_state(State.WANDER)
			else:
				move_target = _flee_target_from(_campfires[fire_index])
	_heard_news = false

## 반경 안 플레이어 지각 한 번에: { nearest_unprotected: Node2D(불 밖 최근접), any_visible: bool }.
## 그룹 조회는 ai_tick_interval 주기로만 일어난다 — 매 프레임 노드 탐색이 아니다 (성능문서 6.3).
func _perceive_players(radius: float) -> Dictionary:
	var nearest_unprotected: Node2D = null
	var best_distance_squared: float = INF
	var any_visible: bool = false
	var candidates: Array[Node2D] = []
	var radius_squared: float = radius * radius
	var local_api: MultiplayerAPI = multiplayer
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player: Node2D = node as Node2D
		if player == null:
			continue
		# 같은 기계(멀티플레이 브랜치)의 플레이어만 지각한다 — 헤드리스 2인 하네스에선
		# 한 트리에 기계가 2개다 (Interactor.find_target 관례).
		if player.multiplayer != local_api:
			continue
		var distance_squared: float = global_position.distance_squared_to(player.global_position)
		if distance_squared > radius_squared:
			continue
		any_visible = true
		if _is_protected_by_fire(player):
			continue
		candidates.append(player)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			nearest_unprotected = player
	var coordinator: Node = _find_pack_coordinator()
	if coordinator != null and coordinator.has_method("choose_visible_target"):
		var pack_target: Node2D = coordinator.choose_visible_target(self, candidates)
		if pack_target != null:
			nearest_unprotected = pack_target
	return { nearest_unprotected = nearest_unprotected, any_visible = any_visible }

## 새 단서가 지금 쫓는 단서를 갈아탈 만한가 (관심도, 설계서 14.1).
## 조사 중이 아니거나 다른 감각의 단서면 무조건 받는다 — 감각 사이 우선순위는
## _ai_tick 의 분기 순서가 이미 정했고, 단위가 다른 세기를 비교하는 것은 무의미하다.
## 같은 감각이면:
##   소리 — 같은 세기여도 받는다. 발소리가 이어지면 가장 최근에 들린 자리가 옳다.
##   냄새 — 더 진할 때만 받는다. 같은 농도로 계속 받으면 경사 정점에서 훑기가 시작되지 않는다.
func _is_more_interesting(kind: StringName, strength: float) -> bool:
	if state != State.INVESTIGATE or kind != _interest_kind:
		return true
	if kind == &"noise":
		return strength >= _interest
	return strength > _interest


## 단서를 채택한다: 목표를 옮기고 훑기 횟수를 처음부터 다시 센다 (재탐색).
func _adopt_cue(kind: StringName, strength: float, target: Vector2) -> void:
	_interest_kind = kind
	_interest = strength
	_search_origin = _clamp_outside_fires(_pack_investigation_target(target))
	_sweeps_left = data.search_sweeps
	move_target = _search_origin
	_change_state(State.INVESTIGATE)


## 조사 지점에 도착했지만 아무것도 없다. 남은 횟수만큼 원점 주변을 훑고,
## 다 훑으면 대상을 상실한다 (배회 복귀).
## ★ 훑기 목표는 _search_origin 과 rng 에서만 나온다. 플레이어 좌표를 보지 않는다.
func _continue_search() -> void:
	if _sweeps_left <= 0:
		_change_state(State.WANDER)
		return
	_sweeps_left -= 1
	var angle: float = rng.randf_range(0.0, TAU)
	var distance: float = rng.randf_range(data.search_radius * 0.4, data.search_radius)
	move_target = _clamp_outside_fires(_search_origin + Vector2.from_angle(angle) * distance)


func _find_smell_grid() -> SmellGrid:
	if _smell_grid == null or not is_instance_valid(_smell_grid):
		_smell_grid = SmellGrid.find_in(get_tree())
	return _smell_grid


func _find_pack_coordinator() -> Node:
	if _pack_coordinator == null or not is_instance_valid(_pack_coordinator):
		_pack_coordinator = get_tree().get_first_node_in_group(&"raptor_pack_coordinator")
	return _pack_coordinator


func _pack_investigation_target(target: Vector2) -> Vector2:
	var coordinator: Node = _find_pack_coordinator()
	if coordinator == null or not coordinator.has_method("assign_investigation_target"):
		return target
	return coordinator.assign_investigation_target(self, target)


## 자기 위치의 냄새 농도 = 냄새 단서의 세기 (관심도 비교용).
func _smell_strength() -> float:
	var grid: SmellGrid = _find_smell_grid()
	return grid.get_smell_at(global_position) if grid != null else 0.0

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

## 다음 배회 목표. 도달 불가능한 지점은 NavigationAgent2D 가 가장 가까운 지점으로 보정한다.
func _pick_wander_target() -> void:
	var angle: float = rng.randf_range(0.0, TAU)
	var distance: float = rng.randf_range(data.wander_range * 0.4, data.wander_range)
	move_target = _clamp_outside_fires(global_position + Vector2.from_angle(angle) * distance)

func _on_campfire_lit(campfire: Node, position: Vector2, radius: float) -> void:
	_on_campfire_extinguished(campfire)
	_campfires.append({node = campfire, position = position, radius = radius})

func _on_campfire_extinguished(campfire: Node) -> void:
	for index: int in range(_campfires.size()):
		if _campfires[index].node == campfire:
			_campfires.remove_at(index)
			return

## pos 가 (반경 * ratio) 안에 드는 가장 가까운 불의 인덱스. 없으면 -1.
## ratio 1.0 은 진입 판정, fire_exit_ratio 는 이탈 판정 — 이 간극이 히스테리시스다.
func _fire_index_containing(pos: Vector2, ratio: float) -> int:
	var best_index: int = -1
	var best_distance: float = INF
	for index: int in range(_campfires.size()):
		var fire: Dictionary = _campfires[index]
		var distance: float = pos.distance_to(fire.position)
		if distance <= fire.radius * ratio and distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index

func _is_protected_by_fire(player: Node2D) -> bool:
	return player != null and _fire_index_containing(player.global_position, 1.0) >= 0

func _start_flee() -> void:
	var fire_index: int = _fire_index_containing(global_position, INF)
	if fire_index >= 0:
		move_target = _flee_target_from(_campfires[fire_index])
	_change_state(State.FLEE)

## 불에서 멀어지는 방향으로 이탈 반경 바깥 지점.
func _flee_target_from(fire: Dictionary) -> Vector2:
	var away: Vector2 = global_position - fire.position
	if away.is_zero_approx():
		away = Vector2.RIGHT
	return fire.position + away.normalized() * fire.radius * data.fire_exit_ratio * 1.15

## 목표 지점이 불 반경 안이면 반경 밖으로 밀어낸다 (불 안으로 들어오지 않는다).
func _clamp_outside_fires(target: Vector2) -> Vector2:
	for fire: Dictionary in _campfires:
		if target.distance_to(fire.position) < fire.radius:
			var away: Vector2 = target - fire.position
			if away.is_zero_approx():
				away = global_position - fire.position
			if away.is_zero_approx():
				away = Vector2.RIGHT
			target = fire.position + away.normalized() * fire.radius * 1.05
	return target

func get_state_name() -> StringName:
	return STATE_NAMES[state]

@rpc("authority", "call_remote", "unreliable")
func apply_raptor_snapshot(position: Vector2, replicated_state: int, target: Vector2) -> void:
	if is_multiplayer_authority():
		return
	if not position.is_finite() or not target.is_finite() or replicated_state < 0 or replicated_state >= State.size():
		return
	_replicated_position = position
	move_target = target
	_change_state(replicated_state)

@rpc("authority", "call_remote", "reliable")
func apply_raptor_state(replicated_state: int, target: Vector2) -> void:
	if is_multiplayer_authority():
		return
	if not target.is_finite() or replicated_state < 0 or replicated_state >= State.size():
		return
	move_target = target
	_change_state(replicated_state)

func _change_state(new_state: int) -> void:
	if state == new_state:
		return
	var previous_state: int = state
	state = new_state
	if new_state != State.INVESTIGATE:
		# 조사를 떠나면 관심도도 사라진다 — 안 그러면 다음 판의 작은 소리가
		# 지난 판의 큰 소리에 눌려 영영 조사를 촉발하지 못한다.
		_interest = 0.0
		_interest_kind = &""
		_sweeps_left = 0
	state_changed.emit(previous_state, new_state)
	if new_state == State.CHASE:
		chase_started.emit()
		_alert_remaining = data.alert_seconds
		if _alert_label != null:
			_alert_label.visible = true
	if is_multiplayer_authority() and multiplayer.get_peers().size() > 0:
		apply_raptor_state.rpc(new_state, move_target)

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
	# 소리의 세기 = 차폐를 반영한 유효 반경. 벽 너머의 큰 소리는 그만큼 덜 끌린다.
	_heard_interest = effective_radius
	_heard_news = true

class_name Interactor
extends Area2D

## Player 의 상호작용 손. interactable 계약을 만족하는 Area2D 를 찾아 실행한다.
##
## interactable 계약 (덕 타이핑):
##   can_interact(who: Node) -> bool
##   get_hold_seconds() -> float      0 이면 즉시 실행
##   get_prompt() -> String           HUD 표시 문구
##   interact(who: Node) -> void      완료 시 1회
##   on_hold_started(who: Node)       (선택) 길게 누르기 시작
##   on_hold_ended(who: Node)         (선택) 취소·완료 무관하게 항상 1회
##
## 선택 표시를 위해 물리 프레임마다 Area2D 의 겹침 캐시만 읽는다. 씬 트리 탐색은 하지 않는다.
## 일반 _process 는 길게 누르는 동안에만 켠다 (성능문서 6.1).

signal hold_changed(ratio: float, label: String)
signal target_changed(target: Node, label: String)

var current_target: Node = null

var _player: Player = null
var _candidates: Array[Node] = []
var _candidate_ids: Array[int] = []
var _cycle_index: int = 0
var _holding: bool = false
var _current_prompt: String = ""
var _hold_elapsed: float = 0.0
var _hold_required: float = 0.0
var _hold_prompt: String = ""
var _target_marker: Polygon2D = null

func _ready() -> void:
	_player = get_parent() as Player
	set_process(false)
	set_physics_process(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		begin()
	elif event.is_action_released("interact"):
		cancel()
	elif event.is_action_pressed("cycle_target"):
		cycle_target()

func _process(delta: float) -> void:
	if not _holding:
		return
	if current_target == null or not is_instance_valid(current_target):
		cancel()
		return

	_hold_elapsed += delta
	if _hold_elapsed < _hold_required:
		hold_changed.emit(_hold_elapsed / _hold_required, _hold_prompt)
		return

	# 완료. interact 를 먼저 실행하고 홀드를 정리한다 — 네트워크 치료 확정(커밋)이
	# 홀드 종료 통지(취소)보다 먼저 호스트에 도착해야 한다 (NetSurvival 세션).
	var target: Node = current_target
	target.interact(_player)
	_end_hold()

## 상호작용 시작. 즉시형이면 그 자리에서 끝나고, 길게 누르는 형이면 홀드에 들어간다.
func begin() -> void:
	if _holding:
		return

	_refresh_candidates()
	var target: Node = current_target
	if target == null:
		return

	var hold: float = target.get_hold_seconds()
	if hold <= 0.0:
		target.interact(_player)
		return

	current_target = target
	_holding = true
	_hold_required = hold
	_hold_elapsed = 0.0
	_hold_prompt = _current_prompt
	_player.movement_locked = true
	if target.has_method("on_hold_started"):
		target.on_hold_started(_player)
	set_process(true)
	hold_changed.emit(0.0, _hold_prompt)

## 완료 전에 손을 떼면 취소된다. 아무 효과도 남기지 않는다.
func cancel() -> void:
	if not _holding:
		return
	_end_hold()

## 사거리 안에서 지금 상호작용 가능한 가장 가까운 대상.
func find_target() -> Node:
	_refresh_candidates()
	return current_target

## 후보는 거리 오름차순, 동거리에서는 인스턴스 ID 오름차순으로 결정론적으로 정렬한다.
func sorted_candidates() -> Array[Node]:
	var candidates: Array[Node] = []
	for area: Area2D in get_overlapping_areas():
		# 헤드리스 2인 하네스에선 한 물리 공간에 기계(멀티플레이 브랜치)가 2개 겹친다.
		# 다른 기계의 대상은 잡지 않는다 — 프로덕션(기계 1개)에선 항상 참이다.
		if area.multiplayer != multiplayer:
			continue
		if not area.has_method("interact") or not area.has_method("can_interact"):
			continue
		if not area.can_interact(_player):
			continue
		candidates.append(area)
	candidates.sort_custom(func(a: Node, b: Node) -> bool:
		var a_distance: float = global_position.distance_squared_to((a as Node2D).global_position)
		var b_distance: float = global_position.distance_squared_to((b as Node2D).global_position)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return a.get_instance_id() < b.get_instance_id()
	)
	return candidates

func cycle_target() -> void:
	if _holding:
		return
	_refresh_candidates()
	if _candidates.size() < 2:
		return
	_cycle_index = (_cycle_index + 1) % _candidates.size()
	_set_current_target(_candidates[_cycle_index])

func _physics_process(_delta: float) -> void:
	if not _holding:
		_refresh_candidates()

func _refresh_candidates() -> void:
	var refreshed: Array[Node] = sorted_candidates()
	var refreshed_ids: Array[int] = []
	for candidate: Node in refreshed:
		refreshed_ids.append(candidate.get_instance_id())

	# 반경 출입(후보 집합/순서 변경)이 생기면 선택은 다시 최근접부터 시작한다.
	if refreshed_ids != _candidate_ids:
		_candidates = refreshed
		_candidate_ids = refreshed_ids
		_cycle_index = 0
		_set_current_target(_candidates[0] if not _candidates.is_empty() else null)
		return

	_candidates = refreshed
	if _candidates.is_empty():
		_cycle_index = 0
		_set_current_target(null)
	elif _cycle_index >= _candidates.size():
		_cycle_index = 0
		_set_current_target(_candidates[0])

func _set_current_target(target: Node) -> void:
	if current_target == target:
		return
	current_target = target
	_current_prompt = _prompt_of(target) if target != null else ""
	_replace_target_marker(target)
	target_changed.emit(target, _current_prompt)

func current_prompt() -> String:
	return _current_prompt

func _replace_target_marker(target: Node) -> void:
	if _target_marker != null and is_instance_valid(_target_marker):
		_target_marker.queue_free()
	_target_marker = null
	if not target is WorldItem:
		return
	var marker := Polygon2D.new()
	marker.name = "InteractionTargetMarker"
	marker.polygon = PackedVector2Array([
		Vector2(-6.0, -24.0), Vector2(6.0, -24.0), Vector2(0.0, -16.0),
	])
	marker.color = Color(1.0, 0.9, 0.2, 0.9)
	marker.z_index = 20
	target.add_child(marker)
	_target_marker = marker

func _end_hold() -> void:
	var target: Node = current_target
	_holding = false
	set_process(false)
	_hold_elapsed = 0.0
	_hold_prompt = ""
	_player.movement_locked = false
	if target != null and is_instance_valid(target) and target.has_method("on_hold_ended"):
		target.on_hold_ended(_player)
	hold_changed.emit(0.0, "")
	_refresh_candidates()

func _prompt_of(target: Node) -> String:
	if target.has_method("get_prompt"):
		return target.get_prompt()
	return ""

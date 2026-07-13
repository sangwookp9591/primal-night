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
## 겹침 조회는 상호작용 키를 누른 순간에만 한다. 매 프레임 노드 탐색을 하지 않는다.
## _process 는 길게 누르는 동안에만 켠다 (성능문서 6.1).

signal hold_changed(ratio: float, label: String)

var current_target: Node = null

var _player: Player = null
var _hold_elapsed: float = 0.0
var _hold_required: float = 0.0
var _hold_prompt: String = ""

func _ready() -> void:
	_player = get_parent() as Player
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		begin()
	elif event.is_action_released("interact"):
		cancel()

func _process(delta: float) -> void:
	if current_target == null or not is_instance_valid(current_target):
		cancel()
		return

	_hold_elapsed += delta
	if _hold_elapsed < _hold_required:
		hold_changed.emit(_hold_elapsed / _hold_required, _hold_prompt)
		return

	# 완료. _end_hold 가 current_target 을 지우므로 먼저 붙잡아 둔다.
	var target: Node = current_target
	_end_hold()
	target.interact(_player)

## 상호작용 시작. 즉시형이면 그 자리에서 끝나고, 길게 누르는 형이면 홀드에 들어간다.
func begin() -> void:
	if current_target != null:
		return

	var target: Node = find_target()
	if target == null:
		return

	var hold: float = target.get_hold_seconds()
	if hold <= 0.0:
		target.interact(_player)
		return

	current_target = target
	_hold_required = hold
	_hold_elapsed = 0.0
	_hold_prompt = _prompt_of(target)
	_player.movement_locked = true
	if target.has_method("on_hold_started"):
		target.on_hold_started(_player)
	set_process(true)
	hold_changed.emit(0.0, _hold_prompt)

## 완료 전에 손을 떼면 취소된다. 아무 효과도 남기지 않는다.
func cancel() -> void:
	if current_target == null:
		return
	_end_hold()

## 사거리 안에서 지금 상호작용 가능한 가장 가까운 대상.
func find_target() -> Node:
	var best: Node = null
	var best_distance: float = INF

	for area: Area2D in get_overlapping_areas():
		if not area.has_method("interact") or not area.has_method("can_interact"):
			continue
		if not area.can_interact(_player):
			continue
		var distance: float = global_position.distance_squared_to(area.global_position)
		if distance < best_distance:
			best_distance = distance
			best = area

	return best

func _end_hold() -> void:
	var target: Node = current_target
	current_target = null
	set_process(false)
	_hold_elapsed = 0.0
	_hold_prompt = ""
	_player.movement_locked = false
	if target != null and is_instance_valid(target) and target.has_method("on_hold_ended"):
		target.on_hold_ended(_player)
	hold_changed.emit(0.0, "")

func _prompt_of(target: Node) -> String:
	if target.has_method("get_prompt"):
		return target.get_prompt()
	return ""

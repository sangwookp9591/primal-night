extends GutTest

## 실기 입력 경로 회귀 테스트.
##
## 기존 test_interactor_target_cycle 은 cycle_target() 을 직접 호출해서 통과했지만,
## 실제 게임에서는 순환이 전혀 되지 않았다. 원인은 project.godot 의 cycle_target 이
## Tab(4194306)이 아니라 BACKSPACE(4194308)에 묶여 있던 것 — 로직이 아니라 바인딩 버그라
## 직접 호출 테스트로는 절대 잡히지 않는다.
##
## 그래서 여기서는 InputEvent 를 Viewport 에 밀어넣어 _unhandled_input 경유로만 검증한다.
## 액션 바인딩이 깨지면 이 테스트가 깨진다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

class Target:
	extends Area2D

	var interact_count: int = 0

	func _init() -> void:
		collision_layer = 4
		collision_mask = 0
		monitoring = false
		var collision := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		collision.shape = circle
		add_child(collision)

	func can_interact(_who: Node) -> bool:
		return true

	func get_hold_seconds() -> float:
		return 0.0

	func get_prompt() -> String:
		return name

	func interact(_who: Node) -> void:
		interact_count += 1

func _spawn_targets() -> Array:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var far := Target.new()
	far.name = "Far"
	far.position = Vector2(40.0, 0.0)
	world.add_child(far)
	var near := Target.new()
	near.name = "Near"
	near.position = Vector2(16.0, 0.0)
	world.add_child(near)
	await wait_physics_frames(2)
	return [player, near, far]

## 플레이어가 실제로 누르는 물리 키를 그대로 밀어넣는다.
##
## InputMap 에서 바인딩을 읽어와 되쏘면 안 된다 — 그러면 "묶인 키를 누르면 묶인 액션이
## 뜬다"는 동어반복이라 바인딩이 BACKSPACE 로 틀어져 있어도 통과한다(실제로 그랬다).
## 키를 리터럴로 적는 게 요점이다: 이 테스트는 'R 을 누르면 순환한다'는
## 플레이어 대면 계약을 고정한다.
func _press_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	get_viewport().push_input(press)


func test_bound_key_is_not_reserved_by_ui_focus_navigation() -> void:
	# Tab 은 내장 ui_focus_next 다. 포커스 가능한 UI 가 생기면 Viewport 가 먼저 먹는다.
	# 순환 키가 그 위로 올라가면 실기에서 조용히 죽으므로 바인딩 단계에서 막는다.
	var events: Array[InputEvent] = InputMap.action_get_events(&"cycle_target")
	assert_gt(events.size(), 0, "cycle_target 바인딩이 있어야 한다")

	for event: InputEvent in events:
		assert_false(event.is_action_pressed(&"ui_focus_next"),
			"cycle_target 은 ui_focus_next(Tab)와 겹치면 안 된다")
		assert_false(event.is_action_pressed(&"ui_focus_prev"),
			"cycle_target 은 ui_focus_prev 와 겹치면 안 된다")


func test_cycle_target_is_bound_to_the_documented_key() -> void:
	# 회귀: 원래 4194308 이 묶여 있었고 그건 Tab 이 아니라 BACKSPACE 였다.
	# 순환 키는 플레이어 대면 계약이므로 바꾸려면 이 테스트도 같이 고치게 둔다.
	var events: Array[InputEvent] = InputMap.action_get_events(&"cycle_target")
	assert_eq(events.size(), 1, "cycle_target 바인딩은 하나여야 한다")
	var bound: InputEventKey = events[0] as InputEventKey
	assert_not_null(bound, "cycle_target 은 키 입력이어야 한다")
	if bound == null:
		return

	var key: Key = bound.physical_keycode if bound.physical_keycode != KEY_NONE else bound.keycode
	assert_eq(key, KEY_R, "대상 순환은 R 이다 (project.godot 주석 참조)")


## 핵심 회귀: 실제 InputEvent 로 순환이 돈다.
func test_pressing_r_cycles_the_target() -> void:
	var spawned: Array = await _spawn_targets()
	var interactor: Interactor = (spawned[0] as Player).interactor
	var near: Target = spawned[1]
	var far: Target = spawned[2]

	interactor.find_target()
	assert_eq(interactor.current_target, near, "전제: 처음에는 최근접 대상")

	_press_key(KEY_R)
	assert_eq(interactor.current_target, far, "R 입력이 _unhandled_input 을 타고 순환시켜야 한다")

	_press_key(KEY_R)
	assert_eq(interactor.current_target, near, "한 바퀴 돌면 최근접으로 돌아온다")


func test_pressing_r_survives_a_physics_frame() -> void:
	# 물리 프레임의 후보 갱신이 선택을 최근접으로 되돌리면 실기에서 순환이 안 보인다.
	var spawned: Array = await _spawn_targets()
	var interactor: Interactor = (spawned[0] as Player).interactor
	var far: Target = spawned[2]

	interactor.find_target()
	_press_key(KEY_R)
	await wait_physics_frames(2)

	assert_eq(interactor.current_target, far, "후보가 그대로면 선택은 프레임을 넘겨 유지된다")


func test_interact_key_still_routes_through_unhandled_input() -> void:
	# 순환 키를 바꾸면서 interact 경로를 깨지 않았는지 같은 방식으로 확인한다.
	var spawned: Array = await _spawn_targets()
	var interactor: Interactor = (spawned[0] as Player).interactor
	var near: Target = spawned[1]

	interactor.find_target()
	_press_key(KEY_E)

	assert_eq(near.interact_count, 1, "E 입력도 _unhandled_input 을 타고 도달해야 한다")


func test_cycled_target_is_what_the_interact_key_picks_up() -> void:
	var spawned: Array = await _spawn_targets()
	var interactor: Interactor = (spawned[0] as Player).interactor
	var near: Target = spawned[1]
	var far: Target = spawned[2]

	interactor.find_target()
	_press_key(KEY_R)
	_press_key(KEY_E)

	assert_eq(near.interact_count, 0, "순환으로 넘긴 대상은 줍지 않는다")
	assert_eq(far.interact_count, 1, "표시된 대상을 줍는다")

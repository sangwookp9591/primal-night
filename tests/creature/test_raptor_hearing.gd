extends GutTest

## 랩터의 소리 지각 (설계서 5.3).
## ★ 공정성 규칙: 공룡은 정확한 좌표를 즉시 알지 못하고,
##   "마지막으로 들은 위치"를 조사한다. 소리 발신자 노드를 추적하지 않는다.
## 차폐: 벽 너머의 소리는 유효 반경이 줄어든다.

const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _make_data() -> CreatureData:
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 50.0
	data.lose_sight_radius = 80.0
	data.smell_threshold = 8.0
	data.ai_tick_interval = 0.2
	data.occlusion_attenuation = 0.5
	return data

func _spawn_raptor(data: CreatureData, at: Vector2) -> Raptor:
	var raptor: Raptor = RaptorScript.new()
	raptor.data = data
	raptor.position = at
	add_child_autofree(raptor)
	return raptor

func _make_wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = at
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	return wall

func test_noise_within_radius_triggers_investigation_of_heard_position() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var noise_position: Vector2 = Vector2(300.0, 0.0)

	_event_bus.noise_emitted.emit(noise_position, 400.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "들리는 소리는 조사를 촉발한다")
	assert_eq(raptor.move_target, noise_position, "목표는 마지막으로 들린 위치다")

func test_investigation_target_is_frozen_not_the_live_source() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var source: Node2D = add_child_autofree(Node2D.new())
	source.position = Vector2(300.0, 0.0)

	_event_bus.noise_emitted.emit(source.position, 400.0, source)
	await wait_physics_frames(2)
	raptor._ai_tick()
	# 발신자가 이동해도 조사 목표는 갱신되면 안 된다 (좌표 실시간 추적 금지).
	source.position = Vector2(-900.0, 500.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "조사는 유지된다")
	assert_eq(raptor.move_target, Vector2(300.0, 0.0), "발신자를 추적하지 않고 들었던 위치만 기억한다")

func test_noise_beyond_radius_is_not_heard() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)

	_event_bus.noise_emitted.emit(Vector2(500.0, 0.0), 100.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "반경 밖 소리는 들리지 않는다")

func test_own_noise_is_ignored() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)

	_event_bus.noise_emitted.emit(raptor.position, 400.0, raptor)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "자기 발소리에 반응하지 않는다")

func test_wall_between_attenuates_noise() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	_make_wall(Vector2(150.0, 0.0), Vector2(20.0, 200.0))
	await wait_physics_frames(2)

	# 거리 300, 반경 400: 트인 곳이면 들리지만
	# 차폐 시 유효 반경 400*0.5=200 < 300 이라 들리지 않는다.
	_event_bus.noise_emitted.emit(Vector2(300.0, 0.0), 400.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "벽 너머 소리는 감쇠되어 들리지 않는다 (설계서 5.3)")

func test_loud_noise_penetrates_wall_with_reduced_radius() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	_make_wall(Vector2(150.0, 0.0), Vector2(20.0, 200.0))
	await wait_physics_frames(2)

	# 거리 300, 반경 800: 차폐 후에도 800*0.5=400 >= 300 이라 들린다.
	_event_bus.noise_emitted.emit(Vector2(300.0, 0.0), 800.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "충분히 큰 소리는 벽 너머에서도 들린다")

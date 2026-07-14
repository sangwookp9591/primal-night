extends GutTest

## 랩터 씬과 이동 (설계서 5.5: 배회는 NavigationAgent2D 로 맵을 돌아다닌다).
## 추격 경고는 화면에 보이는 신호여야 한다 (설계서 3.2).

const RaptorScene: PackedScene = preload("res://scenes/creature/raptor.tscn")
const WorldScene: PackedScene = preload("res://scenes/world/test_world.tscn")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func test_raptor_scene_has_navigation_and_collision() -> void:
	var raptor: Raptor = autofree(RaptorScene.instantiate())

	assert_not_null(raptor.get_node("NavigationAgent2D"), "길찾기는 NavigationAgent2D 를 쓴다")
	assert_not_null(raptor.get_node("CollisionShape2D"), "지형과 충돌해야 한다")
	assert_not_null(raptor.get_node("AlertLabel"), "추격 경고 표시가 있어야 한다")
	assert_eq(raptor.collision_mask & 1, 1, "지형 레이어와 충돌한다")
	assert_not_null(raptor.data, "행동 수치는 데이터 리소스에서 온다")

func test_raptor_walks_toward_the_investigation_target() -> void:
	var world: Node2D = add_child_autofree(WorldScene.instantiate())
	var raptor: Raptor = RaptorScene.instantiate()
	var data: CreatureData = CreatureDataScript.new()
	data.ai_tick_interval = 0.05
	data.walk_speed = 120.0
	raptor.data = data
	# y=900 라인은 test_world 에서 벽이 없는 트인 구간이다 (차폐 없음).
	raptor.position = Vector2(200.0, 900.0)
	world.add_child(raptor)
	await wait_physics_frames(3)

	var noise_position: Vector2 = Vector2(800.0, 900.0)
	_event_bus.noise_emitted.emit(noise_position, 900.0, null)
	await wait_physics_frames(30)

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "소리를 들어 조사 중이어야 한다")
	assert_gt(raptor.global_position.x, 250.0, "들린 위치를 향해 실제로 이동해야 한다")

func test_wander_roams_to_new_targets() -> void:
	var raptor: Raptor = autofree(RaptorScene.instantiate())
	var data: CreatureData = CreatureDataScript.new()
	data.wander_range = 300.0
	data.investigate_arrive_distance = 24.0
	raptor.data = data
	add_child_autofree(raptor)
	raptor.rng.seed = 20260713

	# 배회 중 목표에 도착하면 다음 배회 목표를 고른다.
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER, "배회 상태를 유지한다")
	assert_gt(raptor.move_target.distance_to(raptor.global_position),
		data.investigate_arrive_distance,
		"도착한 배회 목표 대신 새 목표를 골라야 한다 (맵을 돌아다닌다)")

func test_alert_mark_shows_on_chase_and_fades() -> void:
	var raptor: Raptor = RaptorScene.instantiate()
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 200.0
	data.alert_seconds = 0.5
	raptor.data = data
	add_child_autofree(raptor)
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	player.position = Vector2(100.0, 0.0)
	add_child_autofree(player)
	var alert: Label = raptor.get_node("AlertLabel")
	assert_false(alert.visible, "평상시에는 경고가 보이지 않는다")

	raptor._ai_tick()

	assert_true(alert.visible, "추격 전환 순간 경고가 보인다 (설계서 3.2)")

	raptor._physics_process(0.6)

	assert_false(alert.visible, "경고는 잠시 뒤 사라진다")

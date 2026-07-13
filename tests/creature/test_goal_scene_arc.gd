extends GutTest

## 목표 장면 전 구간 상태 아크 (B-01 회귀 방어, 설계서 15장).
## 고정 seed 아래에서 배회 → 조사(냄새 경사 추적) → 추격 → 도주(모닥불)의
## 전 구간이 결정적으로 이어져야 한다. goal_scene_replay 는 실시간 도구라
## CI 관문으로 쓸 수 없으므로, 같은 아크를 틱 단위로 결정적으로 검증한다.

const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")

## goal_scene_replay.gd 의 RAPTOR_RNG_SEED 와 같은 값 (결정성 관문 공유).
const FIXED_SEED: int = 3

var _event_bus: Node = null
var _observed: Array[StringName] = []

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")
	_observed.clear()

func _on_state_changed(_previous_state: int, new_state: int) -> void:
	_observed.append(Raptor.STATE_NAMES[new_state])

func test_goal_scene_arc_investigate_chase_flee_with_fixed_seed() -> void:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2(0.0, 0.0)
	grid.area_size = Vector2(1000.0, 1000.0)
	add_child_autofree(grid)

	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 100.0
	data.lose_sight_radius = 200.0
	data.smell_threshold = 8.0
	data.investigate_arrive_distance = 24.0
	var raptor: Raptor = RaptorScript.new()
	raptor.data = data
	raptor.position = Vector2(450.0, 50.0)
	add_child_autofree(raptor)
	raptor.rng.seed = FIXED_SEED
	raptor.state_changed.connect(_on_state_changed)

	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	player.position = Vector2(50.0, 50.0)
	add_child_autofree(player)
	await wait_physics_frames(1)

	# 1) 배회: 냄새가 없는 동안에는 배회를 유지한다 (고정 seed 로 목표 선택).
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.WANDER, "냄새 전에는 배회한다")

	# 2) 플레이어 부상 — 플레이어 쪽으로 진해지는 피 냄새 띠 (바람 확산의 결과 형상).
	_event_bus.smell_emitted.emit(Vector2(50.0, 50.0), 100.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(150.0, 50.0), 60.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(250.0, 50.0), 30.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(350.0, 50.0), 12.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(450.0, 50.0), 10.0, &"blood")

	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "문턱 이상 냄새로 조사에 진입한다")

	# 3) 경사를 거슬러 접근 (도착 → 재평가 반복) → 시야에 들어오면 추격.
	for step_index: int in range(8):
		if raptor.state != Raptor.State.INVESTIGATE:
			break
		raptor.global_position = raptor.move_target
		raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.CHASE, "냄새를 거슬러 접근하다 시야에 들어오면 추격한다")
	assert_eq(raptor.move_target, player.position, "추격 목표는 지각된 플레이어 위치다")

	# 4) 플레이어가 모닥불 곁으로 — 랩터는 추격을 포기하고 물러난다.
	var campfire: Node = add_child_autofree(Node.new())
	_event_bus.campfire_lit.emit(campfire, player.position, 220.0)
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.FLEE, "플레이어가 불 곁이면 추격을 포기한다")
	assert_gt(raptor.move_target.distance_to(player.position), 220.0,
		"도주 목표는 불 반경 밖이어야 한다")

	var expected: Array[StringName] = [&"investigate", &"chase", &"flee"]
	assert_eq(_observed, expected, "상태 전환 순서가 목표 장면과 같아야 한다")

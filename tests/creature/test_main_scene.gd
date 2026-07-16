extends GutTest

## 메인 씬 통합 계약.
## - 감지 시스템(SmellGrid)과 랩터가 '실제 게임 씬'에 존재해야 한다 (가짜 완료 금지, 설계서 15장).
## - 플레이어 스폰은 벽 밖이어야 하고 4방향으로 실제로 걸을 수 있어야 한다 (코디네이터 BLOCKER).
## - 스폰에서 모닥불 지정자리까지의 직선 경로가 벽에 막히지 않아야 한다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")

const CAMPFIRE_SITE_POSITION: Vector2 = Vector2(-190.0, 330.0)
const MOVE_ACTIONS: Array[StringName] = [&"move_right", &"move_left", &"move_up", &"move_down"]

var _main: Node2D = null

func before_each() -> void:
	_main = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(3)

func after_each() -> void:
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)

func test_main_scene_contains_smell_grid_and_raptor() -> void:
	assert_not_null(_main.get_node_or_null("SmellGrid"), "냄새 격자가 실제 게임 씬에 있어야 한다")
	var raptor: Raptor = _main.get_node_or_null("Raptor") as Raptor
	assert_not_null(raptor, "랩터가 실제 게임 씬에 있어야 한다")

func test_player_spawns_outside_walls_and_can_walk_all_directions() -> void:
	var player: Player = _main.get_node("Player")

	for action: StringName in MOVE_ACTIONS:
		var start_position: Vector2 = player.global_position
		Input.action_press(action)
		await wait_physics_frames(20)
		Input.action_release(action)
		var moved: float = player.global_position.distance_to(start_position)
		assert_gt(moved, 30.0, "%s 방향으로 실제로 걸을 수 있어야 한다 (이동량 %.1fpx)" % [action, moved])

func test_walking_path_from_spawn_to_campfire_site_is_clear() -> void:
	var player: Player = _main.get_node("Player")
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		player.global_position, CAMPFIRE_SITE_POSITION, 1)
	var hit: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(query)

	assert_true(hit.is_empty(), "스폰에서 모닥불 자리까지 직선 경로가 벽에 막히면 안 된다")

func test_raptor_spawns_away_from_player_sight() -> void:
	var player: Player = _main.get_node("Player")
	var raptor: Raptor = _main.get_node("Raptor")
	var distance: float = raptor.global_position.distance_to(player.global_position)

	assert_gt(distance, raptor.data.sight_radius * 2.0,
		"랩터는 시작하자마자 플레이어를 지각하지 못할 만큼 멀리 스폰된다")

## W5-T2: 탈출 지점은 보여야 하고(예고 없는 실패 금지, 설계서 3.2) 벽 안이면 안 된다.
func test_extraction_point_is_visible_and_not_inside_a_wall() -> void:
	var objective: LoopObjective = _main.get_node_or_null("LoopObjective") as LoopObjective
	assert_not_null(objective, "루프 목표가 실제 게임 씬에 있어야 한다")
	assert_true(objective.visible, "탈출 지점 노드가 보여야 한다")
	assert_true(objective.show_extraction_marker, "보이는 탈출 지점 표식이 켜져 있어야 한다")

	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = objective.global_position
	query.collision_mask = 1
	assert_true(objective.get_world_2d().direct_space_state.intersect_point(query).is_empty(),
		"탈출 표식이 벽 안이면 루프를 완주할 수 없다")

## W5-T2: 포획 반경·유예는 코드가 아니라 데이터(씬 인스펙터)로 둔다 — W5-T5 수치 조정용.
func test_loop_objective_carries_capture_tuning_data() -> void:
	var objective: LoopObjective = _main.get_node_or_null("LoopObjective") as LoopObjective
	assert_not_null(objective, "루프 목표가 실제 게임 씬에 있어야 한다")
	assert_gt(objective.capture_radius, 0.0, "포획 반경이 데이터로 설정되어 있어야 한다")
	assert_gt(objective.capture_grace_seconds, 0.0, "포획 유예가 데이터로 설정되어 있어야 한다")

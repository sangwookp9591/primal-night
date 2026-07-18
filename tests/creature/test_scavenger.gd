extends GutTest

const ScavengerScene: PackedScene = preload("res://scenes/creature/scavenger.tscn")
const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")
const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")
const ValleyMapScript = preload("res://scripts/world/valley_map.gd")

func _scavenger(at := Vector2.ZERO) -> Scavenger:
	var scavenger := ScavengerScene.instantiate() as Scavenger
	scavenger.position = at
	add_child_autofree(scavenger)
	scavenger.set_physics_process(false)
	return scavenger

func _carcass(at := Vector2.ZERO) -> Carcass:
	var carcass := CarcassScene.instantiate() as Carcass
	carcass.position = at
	add_child_autofree(carcass)
	return carcass

func test_carcass_attracts_scavenger_and_consumes_one_reward_stage() -> void:
	var scavenger := _scavenger(Vector2.ZERO)
	var carcass := _carcass(Vector2(80.0, 0.0))
	scavenger._ai_tick()
	assert_eq(scavenger.move_target, carcass.global_position, "사체를 먹이 목표로 고른다")
	assert_eq(scavenger.state, Scavenger.State.FORAGE, "도달 전에는 먹지 않는다")
	scavenger.global_position = carcass.global_position
	scavenger._ai_tick()
	assert_eq(scavenger.state, Scavenger.State.EAT)
	scavenger._consume_food()
	assert_eq(carcass.stages_done(), 1, "산출 지급 없이 해체 가능 구간 하나를 잃는다")

func test_smell_grid_gradient_guides_foraging_without_direct_food() -> void:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 32.0
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2.ZERO
	grid.area_size = Vector2(512.0, 512.0)
	add_child_autofree(grid)
	var scavenger := _scavenger(Vector2(16.0, 16.0))
	scavenger._smell_grid = grid
	# 실제 SmellGrid 입력/API를 써서 현재 셀과 동쪽 셀에 농도 경사를 만든다.
	grid._on_smell_emitted(Vector2(16.0, 16.0), 10.0, &"meat")
	grid._on_smell_emitted(Vector2(48.0, 16.0), 80.0, &"meat")
	scavenger._ai_tick()
	assert_gt(scavenger.move_target.x, scavenger.global_position.x,
		"SmellGrid 농도 경사를 따라 냄새 쪽으로 이동한다")

func test_player_approach_causes_non_combat_flee() -> void:
	var scavenger := _scavenger(Vector2.ZERO)
	var player := Node2D.new()
	player.position = Vector2(20.0, 0.0)
	player.add_to_group(&"player")
	add_child_autofree(player)
	scavenger._ai_tick()
	assert_eq(scavenger.state, Scavenger.State.FLEE)
	assert_lt(scavenger.move_target.x, scavenger.global_position.x,
		"플레이어 반대 방향으로 흩어진다")
	assert_false("current_health" in scavenger, "체력/전투 대상이 아닌 도주 전용 생물이다")

func test_eating_emits_noise_and_consumes_smelly_floor_item() -> void:
	var item := WorldItemScene.instantiate() as WorldItem
	item.item_id = &"raw_meat"
	item.count = 2
	add_child_autofree(item)
	var scavenger := _scavenger(item.global_position)
	watch_signals(scavenger)
	scavenger._ai_tick()
	scavenger._consume_food()
	assert_eq(item.count, 1)
	assert_signal_emitted(scavenger, "eating_noise_emitted",
		"먹는 행동은 랩터가 들을 수 있는 NoiseEmitter 경로와 함께 관측 신호를 낸다")

func test_non_authority_cannot_consume_or_run_ai_but_accepts_snapshot() -> void:
	var scavenger := _scavenger(Vector2.ZERO)
	var carcass := _carcass(Vector2(10.0, 0.0))
	scavenger.set_multiplayer_authority(2)
	carcass.set_multiplayer_authority(2)
	scavenger._food_target = carcass
	scavenger._consume_food()
	assert_eq(carcass.stages_done(), 0, "클라이언트 복제본은 보상을 소모하지 못한다")
	scavenger.apply_scavenger_snapshot(Vector2(30.0, 4.0), Scavenger.State.FLEE,
		Vector2(100.0, 4.0))
	assert_eq(scavenger._replicated_position, Vector2(30.0, 4.0))
	assert_eq(scavenger.state, Scavenger.State.FLEE, "권위 스냅샷의 상태를 수용한다")

func test_gentle_resource_axis_slows_scavenging() -> void:
	var scavenger := _scavenger()
	scavenger.apply_difficulty(DifficultyRuntime.preset(&"standard"))
	var standard := scavenger.eating_interval()
	scavenger.apply_difficulty(DifficultyRuntime.preset(&"gentle"))
	assert_eq(scavenger.eating_interval(), standard * 1.5,
		"기존 자원 여유 계수 하나만 연결해 온화에서 더 천천히 먹는다")

func test_main_seeds_the_day_one_z01_scavenger_count() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(main)
	assert_eq(ValleyMapScript.SCAVENGER_DAY_ONE_FORAGE.zone, "Z01")
	assert_eq(main.get_tree().get_nodes_in_group(&"scavenger").filter(
		func(node: Node) -> bool: return main.is_ancestor_of(node)).size(),
		int(ValleyMapScript.SCAVENGER_DAY_ONE_FORAGE.count),
		"valley_map 첫날 Z01 데이터와 실제 소수 스폰 수가 일치한다")

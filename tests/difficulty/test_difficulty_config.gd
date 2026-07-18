extends GutTest

const MainScene: PackedScene = preload("res://scenes/main.tscn")

func before_each() -> void:
	DifficultyRuntime.has_pending_selection = false
	DifficultyRuntime.pending_preset_id = &"standard"
	DifficultyRuntime.current_config = DifficultyRuntime.preset(&"standard")

func test_presets_change_all_connected_rule_axes_without_enemy_health_multiplier() -> void:
	var gentle := DifficultyRuntime.preset(&"gentle")
	var standard := DifficultyRuntime.preset(&"standard")
	var harsh := DifficultyRuntime.preset(&"harsh")
	assert_gt(gentle.resource_spawn_quantity_multiplier, standard.resource_spawn_quantity_multiplier)
	assert_lt(harsh.resource_spawn_quantity_multiplier, standard.resource_spawn_quantity_multiplier)
	assert_lt(gentle.resource_respawn_time_multiplier,
		standard.resource_respawn_time_multiplier)
	assert_gt(harsh.resource_respawn_time_multiplier,
		standard.resource_respawn_time_multiplier)
	assert_gt(gentle.trace_feedback_duration_multiplier, standard.trace_feedback_duration_multiplier)
	assert_lt(harsh.trace_feedback_duration_multiplier, standard.trace_feedback_duration_multiplier)
	assert_gt(gentle.death_item_keep_ratio, standard.death_item_keep_ratio)
	assert_lt(harsh.death_item_keep_ratio, standard.death_item_keep_ratio)
	assert_gt(gentle.raptor_investigate_threshold_multiplier, standard.raptor_investigate_threshold_multiplier)
	assert_lt(harsh.raptor_investigate_threshold_multiplier, standard.raptor_investigate_threshold_multiplier)
	assert_false("enemy_health_multiplier" in gentle)

func test_resource_respawn_timer_uses_difficulty_multiplier() -> void:
	var item := WorldItem.new()
	item.count = 2
	add_child_autofree(item)
	await wait_process_frames(1)
	item.configure_resource_respawn(10.0,
		DifficultyRuntime.preset(&"harsh").resource_respawn_time_multiplier)
	item.deplete()
	assert_almost_eq(item.resource_respawn_seconds, 15.0, 0.001)
	assert_almost_eq(item.respawn_remaining_seconds(), 15.0, 0.001)
	item._process(14.9)
	assert_eq(item.count, 0)
	item._process(0.1)
	assert_eq(item.count, 2)
	assert_true(item.visible)

func test_selected_preset_changes_real_main_scene_variables() -> void:
	DifficultyRuntime.select_for_next_game(&"gentle")
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)
	var runtime := main.get_node("DifficultyRuntime") as DifficultyRuntime
	var bandage := main.get_node("SurvivalDemo/Bandage") as WorldItem
	var raptor := main.get_node("Raptor") as Raptor
	assert_eq(runtime.config.id, &"gentle")
	assert_eq(bandage.count, 3, "기본 2개 자원이 온화 1.5배로 실제 스폰되어야 한다")
	assert_almost_eq(bandage.resource_respawn_seconds, 135.0, 0.001,
		"기본 180초 리스폰에 온화 난이도 0.75배가 실제 적용되어야 한다")
	assert_almost_eq(raptor.data.smell_threshold, 12.0, 0.001)
	assert_almost_eq(raptor.data.chase_give_up_seconds, 0.5, 0.001)

func test_direct_main_load_uses_standard_and_consumes_pending_selection() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)
	assert_eq((main.get_node("DifficultyRuntime") as DifficultyRuntime).config.id, &"standard")

func test_trace_feedback_duration_uses_difficulty_multiplier() -> void:
	var model := SenseIndicatorModel.new()
	model.feedback_duration_multiplier = 1.5
	model.report_noise(Vector2.RIGHT, Vector2.ZERO)
	model.update(SenseIndicatorModel.SOUND_INDICATOR_SECONDS + 1.0)
	assert_true(model.has_recent_sound())
	model.update(2.0)
	assert_false(model.has_recent_sound())

func test_harsh_death_rule_drops_existing_inventory_items_into_the_world() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)
	var runtime := main.get_node("DifficultyRuntime") as DifficultyRuntime
	var player := main.get_node("Player") as Player
	runtime.apply_preset(&"harsh")
	player.inventory.add_item(&"bandage", 3)
	player.health.take_damage(999.0)
	assert_eq(player.inventory.count_of(&"bandage"), 0)
	var dropped := 0
	for item: WorldItem in get_tree().get_nodes_in_group(&"world_item"):
		if main.is_ancestor_of(item) and item.item_id == &"bandage":
			dropped += item.count
	assert_gt(dropped, 3, "기존 스폰 2개에 사망 드롭 3개가 더해져야 한다")

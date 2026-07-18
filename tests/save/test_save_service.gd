extends GutTest

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE := "/tmp/primal_night_slot_1_test.save"

var main: Node
var service: SaveService

func before_each() -> void:
	SaveService.pending_snapshot = {}
	SaveService.pending_death_recovery = false
	SaveService.launch_requested = false
	SaveService.pending_continue_error = ""
	DirAccess.remove_absolute(TEST_SAVE)
	main = add_child_autofree(MainScene.instantiate())
	await wait_process_frames(2)
	service = main.get_node("SaveService") as SaveService
	service.enabled = true
	service.save_path = TEST_SAVE

func after_each() -> void:
	get_tree().paused = false
	DirAccess.remove_absolute(TEST_SAVE)
	SaveService.pending_snapshot = {}
	SaveService.pending_death_recovery = false
	SaveService.launch_requested = false
	SaveService.pending_continue_error = ""

func test_round_trip_restores_all_save_sections_and_player_state() -> void:
	var player := main.get_node("Player") as Player
	var clock := main.get_node("SessionClock") as SessionClock
	var objective := main.get_node("LoopObjective") as LoopObjective
	var chronicle := main.get_node("CharacterChronicle") as CharacterChronicle
	var rack := main.get_node("DryingRack") as DryingRack
	var cache := main.get_node("StorageCache") as StorageCache
	player.global_position = Vector2(12.0, 34.0)
	player.stats.apply_replicated(61.0, 62.0, 63.0, 64.0)
	player.health.apply_replicated(42.0, true)
	player.inventory.add_item(&"wood", 3)
	cache.inventory.add_item(&"fiber", 2)
	rack.apply_state(&"raw_meat", 17.0)
	clock.apply_replicated(2, 481.0, true)
	objective.risk_exposed = true
	objective.bleeding_treated = true
	objective.fire_maintained = true
	objective.record_cause_event(&"noise", Vector2(2.0, 3.0))
	chronicle.scar_count = 2
	chronicle.record_solution(&"escape")
	var expected := service.collect_snapshot()
	assert_true(service.save_now())
	var loaded := SaveService.load_file(TEST_SAVE)
	assert_true(loaded.ok)
	expected = loaded.snapshot
	assert_true(expected.player.equipment.condition_flags is int)
	player.global_position = Vector2.ZERO
	player.stats.apply_replicated(1.0, 1.0, 1.0, 1.0)
	player.health.apply_replicated(1.0, false)
	rack.apply_state(&"", 0.0)
	assert_true(service.apply_snapshot(expected))
	var actual := service.collect_snapshot()
	assert_eq(actual.difficulty, expected.difficulty)
	for key: String in ["player", "clock", "objective", "chronicle", "world_items",
			"campfires", "base_camp", "carcasses", "creatures"]:
		assert_eq(JSON.stringify(actual[key]), JSON.stringify(expected[key]),
			"%s는 실제 JSON 파일 왕복 뒤에도 보존된다" % key)

func test_file_round_trip_restores_food_safety_status() -> void:
	var player := main.get_node("Player") as Player
	player.stats.apply_food_risk(true, 0.75)
	assert_true(service.save_now())
	main.queue_free()
	await wait_process_frames(2)

	assert_true(SaveService.prepare_continue(TEST_SAVE).ok)
	main = add_child_autofree(MainScene.instantiate())
	service = main.get_node("SaveService") as SaveService
	service.save_path = TEST_SAVE
	await wait_process_frames(4)

	player = main.get_node("Player") as Player
	assert_gt(player.stats.food_poison_remaining, 0.0,
		"식중독 잔여 시간은 실제 파일 왕복 뒤에도 복원된다")
	assert_gt(player.stats.poison_remaining, 0.0,
		"중독 잔여 시간은 실제 파일 왕복 뒤에도 복원된다")
	assert_almost_eq(player.stats.poison_potency, 0.75, 0.001)

func test_pending_snapshot_restores_clock_after_fresh_main_is_ready() -> void:
	var clock := main.get_node("SessionClock") as SessionClock
	clock.apply_replicated(1, 77.2, true)
	assert_true(service.save_now())
	main.queue_free()
	await wait_process_frames(2)

	assert_true(SaveService.prepare_continue(TEST_SAVE).ok)
	main = add_child_autofree(MainScene.instantiate())
	service = main.get_node("SaveService") as SaveService
	service.save_path = TEST_SAVE
	await wait_process_frames(4)

	clock = main.get_node("SessionClock") as SessionClock
	assert_almost_eq(clock.time_of_day_seconds, 77.2, 0.2)
	assert_eq(clock.current_phase, SessionClock.Phase.DAYLIGHT)
	assert_almost_eq(clock.remaining_seconds,
		clock.session_duration_seconds() - 77.2, 0.2)

func test_snapshot_phase_restore_does_not_trigger_boundary_autosave() -> void:
	var clock := main.get_node("SessionClock") as SessionClock
	clock.apply_replicated(1, 500.0, true)
	var snapshot := service.collect_snapshot()
	clock.reset()
	var autosave_reasons: Array[StringName] = []
	service.save_completed.connect(
		func(reason: StringName) -> void: autosave_reasons.append(reason))
	assert_true(service.apply_snapshot(snapshot))
	assert_true(autosave_reasons.is_empty(),
		"복원 중 phase 변경은 자동 저장 경계로 취급하지 않는다")

func test_json_integer_schema_is_normalized_in_one_load_layer() -> void:
	var snapshot := service.collect_snapshot()
	snapshot.player.equipment.condition_flags = EquipmentComponent.DAMAGED_FLAG
	snapshot.player.inventory[0] = {"id": "wood", "count": 2}
	snapshot.world_items[0].count = 3
	snapshot.carcasses[0].yield_mask = 5
	snapshot.creatures[0].state = 1
	snapshot.chronicle.solution_counts.escape = 2
	snapshot.chronicle.session_results = [{"outcome": "remain", "day": 2, "cause": ""}]
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()

	var loaded := SaveService.load_file(TEST_SAVE)
	assert_true(loaded.ok)
	assert_true(loaded.snapshot.version is int)
	assert_true(loaded.snapshot.clock.day is int)
	assert_true(loaded.snapshot.objective.outcome is int)
	assert_true(loaded.snapshot.weather.seed is int)
	assert_true(loaded.snapshot.player.equipment.condition_flags is int)
	assert_true(loaded.snapshot.player.inventory[0].count is int)
	assert_true(loaded.snapshot.world_items[0].count is int)
	assert_true(loaded.snapshot.carcasses[0].yield_mask is int)
	assert_true(loaded.snapshot.creatures[0].state is int)
	assert_true(loaded.snapshot.chronicle.solution_counts.escape is int)
	assert_true(loaded.snapshot.chronicle.session_results[0].day is int)

func test_fractional_integer_schema_is_rejected() -> void:
	var snapshot := service.collect_snapshot()
	snapshot.player.equipment.condition_flags = 1.5
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()
	var loaded := SaveService.load_file(TEST_SAVE)
	assert_false(loaded.ok)
	assert_string_contains(loaded.message, "정수")

func test_corrupt_and_version_mismatch_are_safely_rejected() -> void:
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var corrupt := SaveService.load_file(TEST_SAVE)
	assert_false(corrupt.ok)
	assert_string_contains(corrupt.message, "손상")
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 999}))
	file.close()
	var mismatch := SaveService.load_file(TEST_SAVE)
	assert_false(mismatch.ok)
	assert_string_contains(mismatch.message, "버전")

func test_day_night_and_bedding_triggers_autosave() -> void:
	var reasons: Array[StringName] = []
	service.save_completed.connect(func(reason: StringName) -> void: reasons.append(reason))
	var clock := main.get_node("SessionClock") as SessionClock
	clock.phase_changed.emit(SessionClock.Phase.NIGHT)
	(main.get_node("Bedding") as Bedding).rested.emit(main.get_node("Player") as Player)
	assert_eq(reasons, [&"day_night_boundary", &"bedding"])
	assert_true(FileAccess.file_exists(TEST_SAVE))

func test_death_recovery_applies_selected_difficulty_keep_ratio() -> void:
	var player := main.get_node("Player") as Player
	var difficulty := main.get_node("DifficultyRuntime") as DifficultyRuntime
	difficulty.apply_preset(&"gentle")
	player.inventory.add_item(&"wood", 10)
	var snapshot := service.collect_snapshot()
	assert_true(service.apply_snapshot(snapshot, true))
	var kept: int = 0
	for slot: Dictionary in player.inventory.get_transaction_snapshot():
		if slot.get("id", &"") == &"wood":
			kept += int(slot.count)
	assert_eq(kept, floori(10.0 * difficulty.config.death_item_keep_ratio))

func test_json_round_trip_restores_each_difficulty_death_rule() -> void:
	var player := main.get_node("Player") as Player
	var difficulty := main.get_node("DifficultyRuntime") as DifficultyRuntime
	var empty_inventory := player.inventory.get_transaction_snapshot()
	for preset_id: StringName in [&"gentle", &"standard", &"harsh"]:
		assert_true(player.inventory.restore_transaction_snapshot(empty_inventory))
		difficulty.apply_preset(preset_id)
		player.inventory.add_item(&"wood", 10)
		assert_true(service.save_now())
		var loaded := SaveService.load_file(TEST_SAVE)
		assert_true(loaded.ok)
		assert_eq(StringName(loaded.snapshot.difficulty), preset_id)
		assert_true(player.inventory.restore_transaction_snapshot(empty_inventory))
		assert_true(service.apply_snapshot(loaded.snapshot, true))
		assert_eq(player.inventory.count_of(&"wood"),
			floori(10.0 * difficulty.config.death_item_keep_ratio),
			"%s 사망 복구 규칙이 실제 JSON 파일 왕복 뒤 적용된다" % preset_id)

func test_death_record_updates_metadata_without_replacing_checkpoint() -> void:
	var player := main.get_node("Player") as Player
	player.global_position = Vector2(44.0, 55.0)
	assert_true(service.save_now())
	var before: Dictionary = SaveService.load_file(TEST_SAVE).snapshot
	player.global_position = Vector2(999.0, 999.0)
	assert_true(service.record_death("피 냄새가 랩터를 불렀다."))
	var after: Dictionary = SaveService.load_file(TEST_SAVE).snapshot
	assert_eq(after.player, before.player)
	assert_eq(after.death_record.cause, "피 냄새가 랩터를 불렀다.")
	assert_eq(after.chronicle.session_results.back().cause, "피 냄새가 랩터를 불렀다.")

func test_single_pause_stops_tree_and_resume_restores_it() -> void:
	var menu := main.get_node("PauseMenu") as PauseMenu
	menu.open_pause()
	assert_true(get_tree().paused)
	assert_true(menu.visible)
	assert_eq((main.get_node("SessionClock") as SessionClock).process_mode,
		Node.PROCESS_MODE_INHERIT)
	assert_eq((main.get_node("SmellGrid") as SmellGrid).process_mode,
		Node.PROCESS_MODE_INHERIT)
	menu.resume()
	assert_false(get_tree().paused)

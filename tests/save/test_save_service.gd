extends GutTest

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE := "/tmp/primal_night_slot_1_test.save"

var main: Node
var service: SaveService

func before_each() -> void:
	SaveService.pending_snapshot = {}
	SaveService.pending_death_recovery = false
	SaveService.launch_requested = false
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
	player.global_position = Vector2.ZERO
	player.stats.apply_replicated(1.0, 1.0, 1.0, 1.0)
	player.health.apply_replicated(1.0, false)
	rack.apply_state(&"", 0.0)
	assert_true(service.apply_snapshot(expected))
	var actual := service.collect_snapshot()
	assert_eq(actual.difficulty, expected.difficulty)
	assert_eq(actual.player, expected.player)
	assert_eq(actual.clock, expected.clock)
	assert_eq(actual.objective, expected.objective)
	assert_eq(actual.chronicle, expected.chronicle)
	assert_eq(actual.world_items, expected.world_items)
	assert_eq(actual.campfires, expected.campfires)
	assert_eq(actual.base_camp, expected.base_camp)
	assert_eq(actual.carcasses, expected.carcasses)
	assert_eq(actual.creatures, expected.creatures)

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

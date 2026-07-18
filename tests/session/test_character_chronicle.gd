extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")

var root: Node
var player: Player
var chronicle: CharacterChronicle


func before_each() -> void:
	root = add_child_autofree(Node.new())
	player = PlayerScene.instantiate() as Player
	player.name = "Player"
	root.add_child(player)
	chronicle = CharacterChronicle.new()
	chronicle.name = "CharacterChronicle"
	root.add_child(chronicle)
	await wait_process_frames(2)


func test_existing_events_accumulate_scars_repairs_and_principles() -> void:
	var event_bus := get_node("/root/EventBus")
	event_bus.bleeding_started.emit(player)
	event_bus.bleeding_stopped.emit(player)
	assert_eq(chronicle.scar_count, 1)
	assert_true(player.get_node("VisualRig/StateOverlay").visible)

	player.equipment.condition_flags |= EquipmentComponent.DAMAGED_FLAG
	chronicle._outfit_was_damaged = true
	assert_true(player.equipment.repair_outfit())
	assert_eq(chronicle.repaired_outfit_count, 1)

	var knowledge := CraftingKnowledge.ensure_on(player)
	assert_true(knowledge.apply_observation(
		&"craft_bait", &"success", "미끼의 원리를 알았다.", 1.0))
	assert_eq(chronicle.discovered_principle_count, 1)


func test_snapshot_round_trip_preserves_counts_and_result_cause() -> void:
	chronicle.survival_days = 12
	chronicle.scar_count = 3
	chronicle.repaired_outfit_count = 2
	chronicle.discovered_principle_count = 4
	chronicle.record_solution(&"lure")
	chronicle.record_solution(&"lure")
	chronicle.record_solution(&"spear")
	chronicle.record_result(&"death", "피 냄새가 랩터를 불렀다.")
	var saved := chronicle.snapshot()

	var restored := CharacterChronicle.new()
	assert_true(restored.apply_snapshot(saved))
	assert_eq(restored.snapshot(), saved)
	assert_eq(restored.representative_solution(), &"lure")
	assert_eq(restored.session_results[0].cause, "피 냄새가 랩터를 불렀다.")
	restored.free()


func test_reflection_is_short_narrative_not_statistics_screen() -> void:
	chronicle.survival_days = 12
	chronicle.scar_count = 3
	chronicle.record_solution(&"lure")
	var text := chronicle.reflection_text(2)
	assert_eq(text, "12일을 살았다. 흉터 셋.\n창보다 미끼를 믿었다.")
	assert_eq(text.count("\n"), 1)


func test_snapshot_round_trip_preserves_food_safety_status() -> void:
	player.stats.apply_food_risk(true, 0.75)
	var saved := chronicle.snapshot()
	player.stats.clear_food_safety()
	assert_true(chronicle.apply_snapshot(saved))
	assert_gt(player.stats.food_poison_remaining, 0.0)
	assert_gt(player.stats.poison_remaining, 0.0)
	assert_eq(player.stats.poison_potency, 0.75)


func test_distance_sampling_ignores_teleports_and_records_each_slice_zone_once() -> void:
	chronicle.track_position_sample(Vector2.ZERO, "Z01")
	chronicle.track_position_sample(Vector2(30.0, 40.0), "Z01")
	chronicle.track_position_sample(Vector2(60.0, 80.0), "Z02")
	chronicle.track_position_sample(Vector2(1000.0, 1000.0), "Z03")
	chronicle.track_position_sample(Vector2(1010.0, 1000.0), "Z03")

	assert_almost_eq(chronicle.distance_traveled_px, 110.0, 0.001)
	assert_eq(Array(chronicle.visited_zones), ["Z01", "Z02", "Z03"])


func test_timeline_is_bounded_to_eight_and_last_day_filters_old_events() -> void:
	for index: int in range(10):
		chronicle._local_elapsed = float(index) * 100.0
		chronicle.record_timeline("사건 %d을 기억했다." % index)

	assert_eq(chronicle.timeline.size(), CharacterChronicle.TIMELINE_CAPACITY)
	assert_string_contains(chronicle.timeline.front().text, "사건 2")
	chronicle._local_elapsed = 950.0
	var recent := chronicle.last_day_timeline()
	assert_eq(recent.size(), 6)
	assert_string_contains(recent.front().text, "사건 4")


func test_representative_equipment_uses_longest_equipped_duration() -> void:
	chronicle._local_elapsed = 5.0
	assert_eq(player.inventory.add_item(&"work_clothes", 1), 1)
	assert_true(player.equipment.request_equip(&"work_clothes"))
	chronicle._local_elapsed = 25.0
	chronicle.snapshot()

	assert_string_contains(chronicle.representative_equipment_text(), "작업복")


func test_default_reflection_binds_death_summary_sections_and_timeline() -> void:
	chronicle.survival_days = 3
	chronicle.distance_traveled_px = 2450.0
	chronicle.track_position_sample(Vector2.ZERO, "Z01")
	chronicle.record_timeline("불에 익힌 고기를 챙겼다.", &"food")

	var text := chronicle.reflection_text()

	assert_string_contains(text, "생존 3일 · 이동 2.5 km")
	assert_string_contains(text, "발견 지역  Z01")
	assert_string_contains(text, "대표 장비")
	assert_string_contains(text, "주요 사건")
	assert_string_contains(text, "마지막 하루")


func test_death_screen_keeps_cause_and_binds_extended_chronicle_summary() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_process_frames(2)
	var main_chronicle := main.get_node("CharacterChronicle") as CharacterChronicle
	main_chronicle.distance_traveled_px = 1800.0
	main_chronicle.track_position_sample(
		(main.get_node("Player") as Player).global_position, "Z01")
	main_chronicle.record_timeline("상처를 묶어 출혈을 멎게 했다.", &"injury")
	var menu := main.get_node("PauseMenu") as PauseMenu

	menu.show_death("멎지 않은 피 냄새가 랩터를 이끌었다.")
	var screen_text: String = menu._message.text
	get_tree().paused = false

	assert_string_contains(screen_text, "멎지 않은 피 냄새가 랩터를 이끌었다.")
	assert_string_contains(screen_text, "생존 1일 · 이동 1.8 km")
	assert_string_contains(screen_text, "발견 지역  Z01")
	assert_string_contains(screen_text, "주요 사건")
	assert_string_contains(screen_text, "마지막 하루")

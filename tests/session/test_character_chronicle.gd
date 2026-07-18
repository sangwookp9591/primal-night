extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

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

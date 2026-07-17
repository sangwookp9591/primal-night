extends GutTest


func test_first_observation_discovers_recipe_and_records_session_time() -> void:
	var actor: Node = add_child_autofree(Node.new())
	var knowledge: CraftingKnowledge = CraftingKnowledge.ensure_on(actor)

	assert_true(knowledge.apply_observation(
		&"craft_torch", &"hint", "마른 섬유는 잘 감긴다.", 42.5))

	assert_true(knowledge.has_discovered(&"craft_torch"))
	var log: Array[Dictionary] = knowledge.observations()
	assert_eq(log.size(), 1)
	assert_eq(log[0].text, "마른 섬유는 잘 감긴다.")
	assert_almost_eq(float(log[0].session_time), 42.5, 0.001)


func test_same_recipe_observation_kind_is_not_recorded_twice() -> void:
	var actor: Node = add_child_autofree(Node.new())
	var knowledge: CraftingKnowledge = CraftingKnowledge.ensure_on(actor)
	knowledge.apply_observation(&"craft_torch", &"success", "불이 붙었다.", 10.0)

	assert_false(knowledge.apply_observation(
		&"craft_torch", &"success", "다시 불이 붙었다.", 20.0))
	assert_eq(knowledge.discovered_recipe_ids(), [&"craft_torch"])
	assert_eq(knowledge.observations().size(), 1)


func test_snapshot_restores_discovery_and_observation_log() -> void:
	var source_actor: Node = add_child_autofree(Node.new())
	var source: CraftingKnowledge = CraftingKnowledge.ensure_on(source_actor)
	source.apply_observation(&"craft_bait", &"hint", "냄새가 남는다.", 15.0)
	source.apply_observation(&"craft_bait", &"success", "묶어 둘 수 있다.", 18.0)
	var snapshot: Dictionary = source.snapshot()
	var restored_actor: Node = add_child_autofree(Node.new())
	var restored: CraftingKnowledge = CraftingKnowledge.ensure_on(restored_actor)

	assert_true(restored.replace_snapshot(snapshot.discovered,
		snapshot.observation_recipe_ids, snapshot.kinds, snapshot.texts, snapshot.times))
	assert_true(restored.has_discovered(&"craft_bait"))
	assert_eq(restored.observations().size(), 2)

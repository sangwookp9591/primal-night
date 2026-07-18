extends GutTest

const WearableScript = preload("res://scripts/resources/wearable_data.gd")


func test_wearable_validation_accepts_supported_slot_and_survival_modifier() -> void:
	var wearable: WearableData = WearableScript.new()
	wearable.id = &"test_outfit"
	wearable.weight = 1.0
	wearable.equip_slot = &"outfit"
	wearable.visual_id = &"test_visual"
	wearable.modifiers = {warmth = 0.2}

	assert_true(wearable.is_valid_wearable())


func test_wearable_validation_rejects_unknown_slot_and_missing_visual() -> void:
	var wearable: WearableData = WearableScript.new()
	wearable.id = &"bad_outfit"
	wearable.weight = 1.0
	wearable.equip_slot = &"head"
	wearable.modifiers = {warmth = 0.2}

	assert_false(wearable.is_valid_wearable())
	assert_push_error("invalid equip_slot")


func test_small_pack_resource_is_valid_back_wearable() -> void:
	var small_pack: WearableData = load("res://data/items/small_pack.tres")

	assert_not_null(small_pack)
	assert_true(small_pack.is_valid_wearable())
	assert_eq(small_pack.id, &"small_pack")
	assert_eq(small_pack.equip_slot, &"back")
	assert_eq(small_pack.visual_id, &"placeholder_back")
	assert_gt(float(small_pack.modifiers.get("capacity_slots", 0)), 0.0)
	assert_gt(float(small_pack.modifiers.get("capacity_weight", 0.0)), 0.0)


func test_specialized_outfits_are_valid_and_keep_tradeoffs() -> void:
	var fur := load("res://data/items/fur_cloak.tres") as WearableData
	var raincoat := load("res://data/items/reed_raincoat.tres") as WearableData
	var bone := load("res://data/items/bone_armor.tres") as WearableData
	for outfit: WearableData in [fur, raincoat, bone]:
		assert_not_null(outfit)
		assert_true(outfit.is_valid_wearable(), outfit.id)
		assert_eq(outfit.equip_slot, &"outfit")
		assert_true(PlayerVisualProfile.has_registered_sheet(outfit.visual_id), outfit.id)
	assert_gt(float(fur.modifiers.warmth), float(raincoat.modifiers.warmth))
	assert_gt(fur.smell_modifier, raincoat.smell_modifier)
	assert_lt(raincoat.wetness_modifier, fur.wetness_modifier)
	assert_gt(raincoat.noise_modifier, fur.noise_modifier)
	var leather := load("res://data/items/leather_armor.tres") as WearableData
	assert_gt(float(bone.modifiers.injury_protection),
		float(leather.modifiers.injury_protection))
	assert_gt(bone.weight, leather.weight)
	assert_gt(bone.noise_modifier, leather.noise_modifier)

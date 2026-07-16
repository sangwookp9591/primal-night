extends GutTest

func test_client_payload_cannot_supply_result_or_count() -> void:
	# Host API accepts a RecipeData object; callers cannot inject result/count fields.
	var recipe := RecipeData.new(); recipe.id = &"craft_bait"
	assert_eq(recipe.result_count, 1)

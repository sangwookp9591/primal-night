extends GutTest


func test_sinew_is_registered_with_carcass_smell_data() -> void:
	var sinew: ItemData = get_node("/root/GameData").get_item(&"sinew")

	assert_not_null(sinew)
	assert_eq(sinew.get_stack_limit(), 10)
	assert_almost_eq(sinew.weight, 0.2, 0.001)
	assert_true(sinew.is_smell_source())
	assert_almost_eq(sinew.smell_strength, 20.0, 0.001)

extends GutTest
func test_invalid_definition_rejected() -> void:
	var d := ActionDefinition.new(); assert_false(d.is_valid())

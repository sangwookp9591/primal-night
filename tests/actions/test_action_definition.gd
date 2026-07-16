extends GutTest
func test_invalid_definition_rejected() -> void:
	var d := ActionDefinition.new(); assert_false(d.is_valid())
	var bad := ActionDefinition.new(); bad.id = &"x"; bad.duration = -1.0; assert_false(bad.is_valid())

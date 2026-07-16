extends GutTest
func test_one_action_and_cancel_unlocks() -> void:
	var c := ActionController.new(); add_child_autofree(c)
	var d := ActionDefinition.new(); d.id = &"x"; assert_true(c.start(d)); assert_false(c.start(d)); assert_true(c.cancel())

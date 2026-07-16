extends GutTest
func test_unknown_recipe_is_rejected() -> void:
	var c := Crafting.new(); add_child_autofree(c); assert_false(c.craft(null, null))

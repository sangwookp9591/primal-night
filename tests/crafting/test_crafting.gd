extends GutTest
func test_unknown_recipe_is_rejected() -> void:
	var c := Crafting.new(); add_child_autofree(c); assert_false(c.craft(null, null))

func test_recipe_requires_actor_and_recipe() -> void:
	var c := Crafting.new(); add_child_autofree(c)
	var actor := add_child_autofree(Node.new())
	assert_false(c.craft(actor, null))

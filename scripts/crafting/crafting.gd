class_name Crafting
extends Node

signal crafted(recipe_id)

func craft(actor: Node, recipe: RecipeData) -> bool:
	if actor == null or recipe == null or recipe.result == null or recipe.result_count <= 0: return false
	var inv: Inventory = actor.inventory
	for id in recipe.ingredients:
		if not inv.has_item(StringName(id), int(recipe.ingredients[id])): return false
	if inv.total_weight() + recipe.result.weight * recipe.result_count > inv.max_weight: return false
	var can_stack := inv.count_of(recipe.result.id) > 0
	if not can_stack and inv.used_slots() >= inv.slot_count: return false
	if recipe.result_count > recipe.result.get_stack_limit() and not can_stack: return false
	for id in recipe.ingredients: inv.remove_item(StringName(id), int(recipe.ingredients[id]))
	assert(inv.add_item(recipe.result.id, recipe.result_count) == recipe.result_count)
	crafted.emit(recipe.id)
	return true

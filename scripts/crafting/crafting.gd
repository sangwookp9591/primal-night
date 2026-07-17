class_name Crafting
extends Node

signal crafted(recipe_id)

var _noise_emitter := NoiseEmitter.new()


func craft(actor: Node, recipe: RecipeData) -> bool:
	if actor == null or recipe == null or recipe.result == null or recipe.result_count <= 0: return false
	var inv: Inventory = actor.inventory
	for id in recipe.ingredients:
		if not inv.has_item(StringName(id), int(recipe.ingredients[id])): return false
	if not _can_fit_result(inv, recipe): return false
	for id in recipe.ingredients: inv.remove_item(StringName(id), int(recipe.ingredients[id]))
	assert(inv.add_item(recipe.result.id, recipe.result_count) == recipe.result_count)
	_emit_crafting_noise(actor, recipe)
	crafted.emit(recipe.id)
	return true


func _emit_crafting_noise(actor: Node, recipe: RecipeData) -> void:
	if recipe.action == null or recipe.action.noise <= 0.0 or not actor is Node2D:
		return
	var event_bus: Node = get_node_or_null("/root/EventBus")
	if event_bus == null:
		return
	var profile := NoiseProfile.new()
	profile.id = recipe.action.id
	profile.radius = recipe.action.noise
	_noise_emitter.emit_profile(event_bus, profile, (actor as Node2D).global_position, actor)

func _can_fit_result(inv: Inventory, recipe: RecipeData) -> bool:
	var weight: float = inv.total_weight() + recipe.result.weight * recipe.result_count
	for id in recipe.ingredients:
		var item: ItemData = get_node("/root/GameData").get_item(StringName(id))
		if item == null: return false
		weight -= item.weight * float(int(recipe.ingredients[id]))
	if weight > inv.max_weight: return false

	var slots: Array[Dictionary] = []
	for slot in inv._slots:
		slots.append(slot.duplicate())
	for id in recipe.ingredients:
		var remaining: int = int(recipe.ingredients[id])
		for slot: Dictionary in slots:
			if remaining <= 0: break
			if slot.is_empty() or slot["id"] != StringName(id): continue
			var taken: int = mini(int(slot["count"]), remaining)
			slot["count"] = int(slot["count"]) - taken
			remaining -= taken
			if int(slot["count"]) <= 0: slot.clear()

	var remaining_result: int = recipe.result_count
	var limit: int = recipe.result.get_stack_limit()
	for slot: Dictionary in slots:
		if remaining_result <= 0: break
		if slot.is_empty() or slot["id"] != recipe.result.id: continue
		var room: int = limit - int(slot["count"])
		if room > 0: remaining_result -= mini(room, remaining_result)
	for slot: Dictionary in slots:
		if remaining_result <= 0: break
		if slot.is_empty(): remaining_result -= mini(limit, remaining_result)
	return remaining_result <= 0

class_name WaterSource
extends Area2D

const DRINK_HYDRATION: float = 35.0
const HOLD_SECONDS: float = 2.0


func can_interact(who: Node) -> bool:
	return who is Player


func get_hold_seconds() -> float:
	return HOLD_SECONDS


func get_prompt() -> String:
	return "물 뜨기" if _nearby_player_has_empty_skin() else "물 마시기"


func interact(who: Node) -> void:
	var player := who as Player
	if player == null:
		return
	var net := _find_net_harvest()
	if net != null:
		net.request_water(self, player)
		return
	apply_water_action(player)


func apply_water_action(player: Player, forced_action: StringName = &"") -> StringName:
	if player == null:
		return &""
	var action := forced_action
	if action.is_empty():
		action = &"fill" if player.inventory.has_item(&"waterskin", 1) else &"drink"
	if action == &"fill":
		return action if fill_waterskin(player) else &""
	if action != &"drink":
		return &""
	player.stats.restore_water(DRINK_HYDRATION)
	return action


func fill_waterskin(player: Player) -> bool:
	if player == null or not player.inventory.remove_item(&"waterskin", 1):
		return false
	if player.inventory.add_item(&"waterskin_full", 1) != 1:
		player.inventory.add_item(&"waterskin", 1)
		return false
	return true


func _nearby_player_has_empty_skin() -> bool:
	for body: Node2D in get_overlapping_bodies():
		var player := body as Player
		if player != null and player.inventory.has_item(&"waterskin", 1):
			return true
	return false


func _find_net_harvest() -> NetHarvest:
	for node: Node in get_tree().get_nodes_in_group(&"net_harvest"):
		if (node as NetHarvest).owns(self):
			return node as NetHarvest
	return null

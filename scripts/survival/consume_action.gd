class_name ConsumeAction
extends RefCounted

## 섭취 트랜잭션 실행부. 회복량·수량은 ItemData와 호스트 인벤토리만 믿는다.


static func consume(player: Player, item: ItemData, risk_roll: float = -1.0) -> bool:
	if player == null or item == null or not item.is_consumable():
		return false
	if not player.inventory.has_item(item.id, 1):
		return false
	if not player.inventory.remove_item(item.id, 1):
		return false
	if item.id == &"waterskin_full":
		if player.inventory.add_item(&"waterskin_half", 1) != 1:
			player.inventory.add_item(item.id, 1)
			return false
	elif item.id == &"waterskin_half":
		if player.inventory.add_item(&"waterskin", 1) != 1:
			player.inventory.add_item(item.id, 1)
			return false
	player.stats.restore_food(item.nutrition)
	player.stats.restore_water(item.hydration)
	if item.id == &"antidote_salad":
		player.stats.apply_antidote()
	elif item.id == &"marrow_soup":
		player.stats.restore_temperature(25.0)
	var roll := randf() if risk_roll < 0.0 else clampf(risk_roll, 0.0, 1.0)
	player.stats.apply_food_risk(
		item.food_poison_chance > 0.0 and roll < item.food_poison_chance,
		item.poison_potency)
	return true

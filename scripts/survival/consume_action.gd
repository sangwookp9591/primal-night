class_name ConsumeAction
extends RefCounted

## 섭취 트랜잭션 실행부. 회복량·수량은 ItemData와 호스트 인벤토리만 믿는다.


static func consume(player: Player, item: ItemData) -> bool:
	if player == null or item == null or (item.nutrition <= 0.0 and item.hydration <= 0.0):
		return false
	if not player.inventory.has_item(item.id, 1):
		return false
	if not player.inventory.remove_item(item.id, 1):
		return false
	player.stats.restore_food(item.nutrition)
	player.stats.restore_water(item.hydration)
	return true

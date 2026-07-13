class_name WorldItem
extends Area2D

## 월드에 떨어진 아이템. 상호작용으로 즉시 줍는다.
## 자리가 부족하면 들어간 만큼만 줄이고 나머지는 월드에 남긴다 (복제·소실 금지).

@export var item_id: StringName = &"stone"
@export var count: int = 1

var _event_bus: Node = null

func _ready() -> void:
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")

func can_interact(who: Node) -> bool:
	return count > 0 and who is Player

func get_hold_seconds() -> float:
	return 0.0

func get_prompt() -> String:
	# 표시 문구는 ItemData 에서 만든다 (설계서 5.6: UI 하드코딩 금지).
	var item: ItemData = get_node("/root/GameData").get_item(item_id)
	if item == null:
		return ""
	return "%s x%d 줍기" % [item.display_name, count]

func interact(who: Node) -> void:
	var player: Player = who as Player
	if player == null:
		return

	var added: int = player.inventory.add_item(item_id, count)
	if added <= 0:
		return

	count -= added
	if _event_bus != null:
		_event_bus.item_picked_up.emit(item_id, player)

	if count <= 0:
		queue_free()

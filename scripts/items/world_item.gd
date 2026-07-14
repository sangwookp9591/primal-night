class_name WorldItem
extends Area2D

## 월드에 떨어진 아이템. 상호작용으로 즉시 줍는다.
## 자리가 부족하면 들어간 만큼만 줄이고 나머지는 월드에 남긴다 (복제·소실 금지).

@export var item_id: StringName = &"stone"
@export var count: int = 1

var _event_bus: Node = null
var _net_pickup: NetPickup = null
var _net_pickup_cached: bool = false

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

	# 넷 스택이 있으면 획득 판정·복제는 호스트 권위 경로로 간다 (설계서 7.2).
	var net: NetPickup = _find_net_pickup()
	if net != null:
		net.request(self, player)
		return
	apply_pickup(player)

## 로컬 적용 (넷 스택이 없는 씬의 즉시 획득 + 호스트 권위 판정의 실행부).
## 실제로 들어간 개수를 반환한다.
func apply_pickup(player: Player) -> int:
	var added: int = player.inventory.add_item(item_id, count)
	if added <= 0:
		return 0

	count -= added
	if _event_bus != null:
		_event_bus.item_picked_up.emit(item_id, player)

	if count <= 0:
		queue_free()
	return added

## 같은 기계(멀티플레이 브랜치)의 NetPickup 만 잡는다 — 헤드리스 하네스에선
## 한 트리에 기계가 2개다. 상호작용 시점에만 1회 조회하고 캐시한다 (성능문서 6.1).
func _find_net_pickup() -> NetPickup:
	if _net_pickup_cached:
		return _net_pickup
	_net_pickup_cached = true
	for node: Node in get_tree().get_nodes_in_group(&"net_pickup"):
		if (node as NetPickup).owns(self):
			_net_pickup = node as NetPickup
			break
	return _net_pickup

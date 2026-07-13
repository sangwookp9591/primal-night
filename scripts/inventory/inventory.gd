class_name Inventory
extends Node

## 8칸 슬롯 인벤토리 (프로토타입. 출시는 16칸 — 설계서 5.8).
##
## 불변식 (tests/inventory/test_inventory.gd 가 검증한다):
##   1. 슬롯은 slot_count 개를 넘지 않는다.
##   2. 한 슬롯의 수량은 ItemData.get_stack_limit() 을 넘지 않는다.
##   3. 수량은 음수가 되지 않는다.
##
## 수량은 GameData 에 등록된 ItemData 로만 검증한다. 등록되지 않은 id 는
## 조용히 기본값으로 대체하지 않고 거부한다 (설계서 13장).

## HUD 는 이 신호로만 갱신한다. 매 프레임 폴링하지 않는다 (성능문서 6.2).
signal changed()

@export var slot_count: int = 8

## 슬롯은 _ready 에서 한 번만 할당하고 이후에는 제자리에서 수정한다.
## 획득/소비마다 새 Dictionary 를 만들지 않는다 (성능문서 6.1).
var _slots: Array[Dictionary] = []
var _game_data: Node = null

func _ready() -> void:
	_game_data = get_node("/root/GameData")
	_slots.resize(slot_count)
	for i: int in range(slot_count):
		_slots[i] = {}

## 실제로 들어간 개수를 반환한다. 자리가 부족하면 들어간 만큼만 반환한다.
func add_item(id: StringName, count: int) -> int:
	if count <= 0:
		return 0

	var item: ItemData = _game_data.get_item(id)
	if item == null:
		return 0

	var limit: int = item.get_stack_limit()
	var remaining: int = count

	# 1) 기존 스택을 먼저 채운다. 새 슬롯을 낭비하지 않는다.
	for slot: Dictionary in _slots:
		if remaining <= 0:
			break
		if slot.is_empty() or slot["id"] != id:
			continue
		var room: int = limit - int(slot["count"])
		if room <= 0:
			continue
		var moved: int = mini(room, remaining)
		slot["count"] = int(slot["count"]) + moved
		remaining -= moved

	# 2) 남으면 빈 슬롯에 새 스택을 만든다. 슬롯이 없으면 거기서 끝난다.
	for slot: Dictionary in _slots:
		if remaining <= 0:
			break
		if not slot.is_empty():
			continue
		var moved: int = mini(limit, remaining)
		slot["id"] = id
		slot["count"] = moved
		remaining -= moved

	var added: int = count - remaining
	if added > 0:
		changed.emit()
	return added

## 전부 아니면 전무. 보유량이 부족하면 아무것도 건드리지 않고 false 를 반환한다.
func remove_item(id: StringName, count: int) -> bool:
	if count <= 0 or count_of(id) < count:
		return false

	var remaining: int = count
	for slot: Dictionary in _slots:
		if remaining <= 0:
			break
		if slot.is_empty() or slot["id"] != id:
			continue
		var taken: int = mini(int(slot["count"]), remaining)
		slot["count"] = int(slot["count"]) - taken
		remaining -= taken
		if int(slot["count"]) <= 0:
			slot.clear()

	changed.emit()
	return true

func count_of(id: StringName) -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		if not slot.is_empty() and slot["id"] == id:
			total += int(slot["count"])
	return total

func has_item(id: StringName, count: int) -> bool:
	return count_of(id) >= count

## HUD 용 읽기 전용 조회. 비어 있으면 빈 Dictionary.
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		return {}
	return _slots[index]

func used_slots() -> int:
	var used: int = 0
	for slot: Dictionary in _slots:
		if not slot.is_empty():
			used += 1
	return used

func total_weight() -> float:
	var total: float = 0.0
	for slot: Dictionary in _slots:
		if slot.is_empty():
			continue
		var item: ItemData = _game_data.get_item(slot["id"])
		if item != null:
			total += item.weight * float(slot["count"])
	return total

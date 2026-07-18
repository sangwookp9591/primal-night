class_name EquipmentComponent
extends Node

signal equipment_changed(slot: StringName, item_id: StringName)

const SLOTS: Array[StringName] = [&"outfit", &"back", &"main_hand"]
const EMPTY_ITEM: StringName = &""
const DAMAGED_FLAG: int = 1 << 3

@export var inventory_path: NodePath = ^"../Inventory"
@export var starting_item_id: StringName = &""

var condition_flags: int = 0
var _equipped: Dictionary = {
	outfit = EMPTY_ITEM,
	back = EMPTY_ITEM,
	main_hand = EMPTY_ITEM,
}
var _inventory: Inventory = null
var _game_data: Node = null


func _ready() -> void:
	_game_data = get_node("/root/GameData")
	_inventory = get_node_or_null(inventory_path) as Inventory
	if starting_item_id != &"":
		_confirm_starting_item(starting_item_id)


## 이후 네트워크 계층은 이 단일 요청 진입점만 호스트에서 호출하면 된다.
func request_equip(item_id: StringName) -> bool:
	var command: Dictionary = _validate_equip_request(item_id)
	if command.is_empty():
		return false
	return _commit_equip(command)


func request_unequip(slot: StringName) -> bool:
	var command: Dictionary = _validate_unequip_request(slot)
	if command.is_empty():
		return false
	return _commit_unequip(command)


# 기존 호출자와 문서 용어를 위한 짧은 별칭.
func equip(item_id: StringName) -> bool:
	return request_equip(item_id)


func unequip(slot: StringName) -> bool:
	return request_unequip(slot)


func get_equipped(slot: StringName) -> StringName:
	if not SLOTS.has(slot):
		push_warning("EquipmentComponent: unknown slot %s" % slot)
		return EMPTY_ITEM
	return StringName(_equipped[slot])


func get_snapshot() -> Dictionary:
	return {
		outfit = StringName(_equipped.outfit),
		back = StringName(_equipped.back),
		main_hand = StringName(_equipped.main_hand),
		condition_flags = condition_flags,
	}


func can_repair_outfit() -> bool:
	return get_equipped(&"outfit") != EMPTY_ITEM and (condition_flags & DAMAGED_FLAG) != 0


func repair_outfit() -> bool:
	if not can_repair_outfit():
		return false
	condition_flags &= ~DAMAGED_FLAG
	equipment_changed.emit(&"outfit", get_equipped(&"outfit"))
	return true


## 저장/복제 공통 경로. 전체를 먼저 검증하고 전부 유효할 때만 확정한다.
func apply_snapshot(snapshot: Dictionary) -> bool:
	for key: StringName in SLOTS:
		if not snapshot.has(key):
			push_error("EquipmentComponent: snapshot missing slot %s" % key)
			return false
		var item_id := StringName(snapshot[key])
		if item_id == &"":
			continue
		var wearable: WearableData = _get_wearable(item_id)
		if wearable == null or wearable.equip_slot != key:
			push_error("EquipmentComponent: invalid snapshot item %s for %s" % [item_id, key])
			return false
	var flags: Variant = snapshot.get("condition_flags", 0)
	if not (flags is int) or int(flags) < 0:
		push_error("EquipmentComponent: invalid condition_flags")
		return false

	var previous: Dictionary = get_snapshot()
	for key: StringName in SLOTS:
		_equipped[key] = StringName(snapshot[key])
	condition_flags = int(flags)
	for key: StringName in SLOTS:
		if previous[key] != _equipped[key]:
			equipment_changed.emit(key, _equipped[key])
	return true


func _validate_equip_request(item_id: StringName) -> Dictionary:
	if _inventory == null:
		push_error("EquipmentComponent: inventory unavailable")
		return {}
	var wearable: WearableData = _get_wearable(item_id)
	if wearable == null or not wearable.is_valid_wearable():
		return {}
	if not _inventory.has_item(item_id, 1):
		return {}
	return {item_id = item_id, slot = wearable.equip_slot, previous = get_equipped(wearable.equip_slot)}


func _validate_unequip_request(slot: StringName) -> Dictionary:
	if _inventory == null or not SLOTS.has(slot):
		return {}
	var item_id: StringName = get_equipped(slot)
	if item_id == &"":
		return {}
	return {item_id = item_id, slot = slot}


func _commit_equip(command: Dictionary) -> bool:
	var inventory_before: Array[Dictionary] = _inventory.get_transaction_snapshot()
	var slot: StringName = command.slot
	var item_id: StringName = command.item_id
	var previous: StringName = command.previous
	if not _inventory.remove_item(item_id, 1):
		return false
	if previous != &"" and _inventory.add_item(previous, 1) != 1:
		_inventory.restore_transaction_snapshot(inventory_before)
		return false
	_equipped[slot] = item_id
	equipment_changed.emit(slot, item_id)
	return true


func _commit_unequip(command: Dictionary) -> bool:
	var inventory_before: Array[Dictionary] = _inventory.get_transaction_snapshot()
	var item_id: StringName = command.item_id
	if _inventory.add_item(item_id, 1) != 1:
		_inventory.restore_transaction_snapshot(inventory_before)
		return false
	var slot: StringName = command.slot
	_equipped[slot] = EMPTY_ITEM
	equipment_changed.emit(slot, EMPTY_ITEM)
	return true


func _confirm_starting_item(item_id: StringName) -> void:
	var wearable: WearableData = _get_wearable(item_id)
	if wearable == null or not wearable.is_valid_wearable():
		push_error("EquipmentComponent: invalid starting item %s; leaving slot empty" % item_id)
		return
	_equipped[wearable.equip_slot] = item_id
	equipment_changed.emit(wearable.equip_slot, item_id)


func _get_wearable(item_id: StringName) -> WearableData:
	var item: ItemData = _game_data.get_item(item_id)
	if item == null:
		return null
	if not item is WearableData:
		push_warning("EquipmentComponent: item %s is not wearable" % item_id)
		return null
	return item as WearableData

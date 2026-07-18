extends GutTest

const EquipmentScript = preload("res://scripts/equipment/equipment_component.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func _make_pair() -> Dictionary:
	var root := Node.new()
	add_child_autofree(root)
	var inventory: Inventory = InventoryScript.new()
	inventory.name = "Inventory"
	root.add_child(inventory)
	var equipment: EquipmentComponent = EquipmentScript.new()
	equipment.name = "EquipmentComponent"
	root.add_child(equipment)
	return {inventory = inventory, equipment = equipment}


func test_equip_and_unequip_exchange_inventory_atomically() -> void:
	var pair: Dictionary = _make_pair()
	var inventory: Inventory = pair.inventory
	var equipment: EquipmentComponent = pair.equipment
	inventory.add_item(&"white_underwear", 1)

	assert_true(equipment.request_equip(&"white_underwear"))
	assert_eq(inventory.count_of(&"white_underwear"), 0)
	assert_eq(equipment.get_equipped(&"outfit"), &"white_underwear")
	assert_true(equipment.request_unequip(&"outfit"))
	assert_eq(inventory.count_of(&"white_underwear"), 1)
	assert_eq(equipment.get_equipped(&"outfit"), &"")


func test_failed_swap_rolls_back_inventory_and_equipment_without_loss_or_duplication() -> void:
	var pair: Dictionary = _make_pair()
	var inventory: Inventory = pair.inventory
	var equipment: EquipmentComponent = pair.equipment
	inventory.add_item(&"white_underwear", 1)
	assert_true(equipment.request_equip(&"white_underwear"))
	inventory.add_item(&"wood", 1)
	var before_inventory: Array[Dictionary] = inventory.get_transaction_snapshot()
	var before_equipment: Dictionary = equipment.get_snapshot()

	# wood 는 WearableData 가 아니므로 검증 단계에서 상태를 전혀 건드리지 않아야 한다.
	# (torch 는 main_hand 착용 장비로 승격되어 더 이상 비착용 픽스처가 아니다.)
	assert_false(equipment.request_equip(&"wood"))

	assert_eq(inventory.get_transaction_snapshot(), before_inventory)
	assert_eq(equipment.get_snapshot(), before_equipment)


func test_failed_unequip_rolls_back_when_inventory_cannot_accept_item() -> void:
	var pair: Dictionary = _make_pair()
	var inventory: Inventory = pair.inventory
	var equipment: EquipmentComponent = pair.equipment
	inventory.add_item(&"white_underwear", 1)
	assert_true(equipment.request_equip(&"white_underwear"))
	inventory.max_weight = 0.0
	var before_inventory: Array[Dictionary] = inventory.get_transaction_snapshot()

	assert_false(equipment.request_unequip(&"outfit"))
	assert_eq(inventory.get_transaction_snapshot(), before_inventory)
	assert_eq(equipment.get_equipped(&"outfit"), &"white_underwear")


func test_snapshot_round_trip_uses_small_stable_shape() -> void:
	var pair: Dictionary = _make_pair()
	var equipment: EquipmentComponent = pair.equipment
	var snapshot := {
		outfit = &"white_underwear",
		back = &"",
		main_hand = &"",
		condition_flags = 5,
	}

	assert_true(equipment.apply_snapshot(snapshot))
	assert_eq(equipment.get_snapshot(), snapshot)


func test_small_pack_equips_to_back_slot() -> void:
	var pair: Dictionary = _make_pair()
	var inventory: Inventory = pair.inventory
	var equipment: EquipmentComponent = pair.equipment
	inventory.add_item(&"small_pack", 1)

	assert_true(equipment.request_equip(&"small_pack"))
	assert_eq(inventory.count_of(&"small_pack"), 0)
	assert_eq(equipment.get_equipped(&"back"), &"small_pack")


func test_player_starts_with_white_underwear_equipped() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	assert_eq(player.equipment.get_equipped(&"outfit"), &"white_underwear")
	assert_eq(player.equipment.get_snapshot()["condition_flags"], 0)


func test_unknown_ids_are_rejected_without_mutating_state() -> void:
	var pair: Dictionary = _make_pair()
	var equipment: EquipmentComponent = pair.equipment
	var before: Dictionary = equipment.get_snapshot()

	assert_false(equipment.request_equip(&"unknown_equipment"))
	assert_eq(equipment.get_snapshot(), before)
	assert_push_error("Missing item data")

	assert_false(equipment.apply_snapshot({
		outfit = &"unknown_equipment",
		back = &"",
		main_hand = &"",
		condition_flags = 0,
	}))
	assert_eq(equipment.get_snapshot(), before)
	assert_push_error("Missing item data")
	assert_push_error("invalid snapshot item")

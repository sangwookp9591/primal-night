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
	assert_eq(inventory.slot_count, 20)
	assert_almost_eq(inventory.max_weight, 28.0, 0.001)


func test_small_pack_unequip_is_rejected_when_contracted_capacity_would_overflow() -> void:
	var pair: Dictionary = _make_pair()
	var inventory: Inventory = pair.inventory
	var equipment: EquipmentComponent = pair.equipment
	assert_eq(inventory.add_item(&"small_pack", 1), 1)
	assert_true(equipment.request_equip(&"small_pack"))
	# 21kg fits the 28kg pack limit but not the contracted 20kg base limit.
	assert_eq(inventory.add_item(&"fiber", 210), 210)
	var before: Array[Dictionary] = inventory.get_transaction_snapshot()

	assert_false(equipment.request_unequip(&"back"))
	assert_eq(equipment.get_equipped(&"back"), &"small_pack")
	assert_eq(inventory.slot_count, 20)
	assert_eq(inventory.get_transaction_snapshot(), before)


func test_small_pack_unequip_compacts_expanded_slots_when_contents_fit() -> void:
	var pair: Dictionary = _make_pair()
	var inventory: Inventory = pair.inventory
	var equipment: EquipmentComponent = pair.equipment
	assert_eq(inventory.add_item(&"small_pack", 1), 1)
	assert_true(equipment.request_equip(&"small_pack"))
	assert_eq(inventory.add_item(&"fiber", 10), 10)

	assert_true(equipment.request_unequip(&"back"))
	assert_eq(inventory.slot_count, 16)
	assert_almost_eq(inventory.max_weight, 20.0, 0.001)
	assert_eq(inventory.count_of(&"fiber"), 10)
	assert_eq(inventory.count_of(&"small_pack"), 1)


func test_expanded_inventory_and_equipment_snapshot_restore_in_save_order() -> void:
	var source: Dictionary = _make_pair()
	assert_eq(source.inventory.add_item(&"small_pack", 1), 1)
	assert_true(source.equipment.request_equip(&"small_pack"))
	assert_eq(source.inventory.add_item(&"fiber", 210), 210)
	var inventory_snapshot: Array[Dictionary] = source.inventory.get_transaction_snapshot()
	var equipment_snapshot: Dictionary = source.equipment.get_snapshot()

	var restored: Dictionary = _make_pair()
	# SaveService restores inventory first and equipment second.
	assert_true(restored.inventory.restore_transaction_snapshot(inventory_snapshot))
	assert_true(restored.equipment.apply_snapshot(equipment_snapshot))

	assert_eq(restored.inventory.slot_count, 20)
	assert_almost_eq(restored.inventory.max_weight, 28.0, 0.001)
	assert_eq(restored.inventory.count_of(&"fiber"), 210)
	assert_eq(restored.equipment.get_equipped(&"back"), &"small_pack")


func test_player_starts_with_white_underwear_equipped() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	assert_eq(player.equipment.get_equipped(&"outfit"), &"white_underwear")
	assert_eq(player.equipment.get_snapshot()["condition_flags"], 0)


func test_bone_armor_reduces_host_physical_damage_to_thirty_five_percent() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.inventory.add_item(&"bone_armor", 1)
	assert_true(player.equipment.request_equip(&"bone_armor"))
	var before: float = player.health.current_health

	player.health.take_damage(40.0, &"debug")

	assert_almost_eq(player.health.current_health, before - 14.0, 0.001)


func test_bone_armor_does_not_reduce_ongoing_bleed_damage() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.inventory.add_item(&"bone_armor", 1)
	assert_true(player.equipment.request_equip(&"bone_armor"))
	var before: float = player.health.current_health

	player.health.take_damage(10.0, &"bleed")

	assert_almost_eq(player.health.current_health, before - 10.0, 0.001)


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

extends GutTest

const InventoryScript = preload("res://scripts/inventory/inventory.gd")

var _game_data: Node

func before_each() -> void:
	_game_data = get_node("/root/GameData")

func _make_inventory(max_weight: float) -> Inventory:
	var inventory: Inventory = InventoryScript.new()
	inventory.max_weight = max_weight
	add_child_autofree(inventory)
	return inventory

func test_accepts_item_at_exact_weight_boundary() -> void:
	var item: ItemData = _game_data.get_item(&"bandage")
	var inventory: Inventory = _make_inventory(item.weight * 3.0)

	assert_eq(inventory.add_item(item.id, 3), 3)
	assert_almost_eq(inventory.total_weight(), inventory.max_weight, 0.001)

func test_weight_limit_partially_accepts_request() -> void:
	var inventory: Inventory = _make_inventory(3.0)

	var added: int = inventory.add_item(&"stone", 5)

	assert_eq(added, 3, "무게 상한까지 일부만 획득해야 한다")
	assert_eq(inventory.count_of(&"stone"), 3)

func test_rejects_zero_weight_item_data() -> void:
	var inventory: Inventory = _make_inventory(10.0)
	var item: ItemData = _game_data.get_item(&"bandage")
	var original_weight: float = item.weight
	item.weight = 0.0

	var added: int = inventory.add_item(item.id, 1)

	item.weight = original_weight
	assert_eq(added, 0)
	assert_eq(inventory.used_slots(), 0)
	assert_push_error("invalid weight")

func test_rejects_negative_weight_item_data() -> void:
	var inventory: Inventory = _make_inventory(10.0)
	var item: ItemData = _game_data.get_item(&"bandage")
	var original_weight: float = item.weight
	item.weight = -1.0

	var added: int = inventory.add_item(item.id, 1)

	item.weight = original_weight
	assert_eq(added, 0)
	assert_eq(inventory.used_slots(), 0)
	assert_push_error("invalid weight")

func test_rejects_item_when_weight_is_full_despite_free_slots() -> void:
	var inventory: Inventory = _make_inventory(1.0)
	inventory.add_item(&"stone", 1)

	assert_eq(inventory.add_item(&"wood", 1), 0)
	assert_eq(inventory.used_slots(), 1, "빈 슬롯이 있어도 무게가 차면 거부해야 한다")

func test_removal_restores_weight_capacity() -> void:
	var inventory: Inventory = _make_inventory(2.0)
	inventory.add_item(&"stone", 2)

	assert_true(inventory.remove_item(&"stone", 1))
	assert_eq(inventory.add_item(&"stone", 1), 1)
	assert_almost_eq(inventory.total_weight(), 2.0, 0.001)

func test_partial_pickup_preserves_requested_total() -> void:
	var inventory: Inventory = _make_inventory(3.0)
	var requested: int = 5

	var added: int = inventory.add_item(&"stone", requested)
	var remaining: int = requested - added

	assert_eq(added + remaining, requested, "획득량과 월드 잔량의 합이 요청 총량이어야 한다")
	assert_eq(remaining, 2)

func test_capacity_is_recalculated_from_item_data() -> void:
	var inventory: Inventory = _make_inventory(3.0)
	var item: ItemData = _game_data.get_item(&"stone")
	var original_weight: float = item.weight
	inventory.add_item(item.id, 2)
	item.weight = 1.5

	var added: int = inventory.add_item(item.id, 1)

	item.weight = original_weight
	assert_eq(added, 0, "캐시된 무게가 아니라 현재 ItemData.weight 로 다시 계산해야 한다")

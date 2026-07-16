extends GutTest

## 인벤토리 불변식: 슬롯 초과 금지 / 스택 상한 준수 / 음수 수량 금지.
## 수치는 GameData 에 등록된 실제 .tres 에서 온다. 테스트도 하드코딩하지 않는다.

const InventoryScript = preload("res://scripts/inventory/inventory.gd")

var _game_data: Node = null

func before_each() -> void:
	_game_data = get_node("/root/GameData")

func _make_inventory() -> Inventory:
	var inventory: Inventory = InventoryScript.new()
	add_child_autofree(inventory)
	return inventory

func _stack_limit(id: StringName) -> int:
	var item: ItemData = _game_data.get_item(id)
	return item.get_stack_limit()

func test_game_data_registers_the_three_prototype_items() -> void:
	for id: StringName in [&"stone", &"wood", &"bandage"]:
		var item: ItemData = _game_data.get_item(id)
		assert_not_null(item, "GameData 에 %s 가 등록되어 있어야 한다" % id)
		assert_eq(item.id, id, "ItemData.id 가 조회 키와 일치해야 한다")
		assert_ne(item.display_name, "", "표시 이름이 데이터에 있어야 한다 (UI 하드코딩 금지)")
		assert_gt(item.get_stack_limit(), 0, "스택 상한은 1 이상이어야 한다")

func test_starts_empty_with_sixteen_slots() -> void:
	var inventory: Inventory = _make_inventory()

	assert_eq(inventory.slot_count, 16, "출시 인벤토리는 16칸이다")
	assert_eq(inventory.used_slots(), 0, "처음에는 빈 상태여야 한다")
	for i: int in range(16):
		assert_true(inventory.get_slot(i).is_empty(), "슬롯 %d 는 비어 있어야 한다" % i)

func test_add_item_returns_amount_added_and_is_countable() -> void:
	var inventory: Inventory = _make_inventory()

	var added: int = inventory.add_item(&"stone", 3)

	assert_eq(added, 3, "요청한 3개가 모두 들어가야 한다")
	assert_eq(inventory.count_of(&"stone"), 3, "3개를 보유해야 한다")
	assert_eq(inventory.used_slots(), 1, "돌 3개는 한 슬롯이면 충분하다")

func test_add_emits_changed() -> void:
	var inventory: Inventory = _make_inventory()
	watch_signals(inventory)

	inventory.add_item(&"stone", 1)

	assert_signal_emitted(inventory, "changed", "인벤토리가 바뀌면 changed 를 발신해야 한다 (HUD 는 신호로 갱신)")

## ★ 불변식: 스택 상한 준수. 상한을 넘으면 다음 슬롯으로 넘긴다.
func test_stack_respects_max_stack_and_spills_to_next_slot() -> void:
	var inventory: Inventory = _make_inventory()
	var limit: int = _stack_limit(&"bandage")

	var added: int = inventory.add_item(&"bandage", limit + 2)

	assert_eq(added, limit + 2, "두 슬롯에 나눠 담으면 전부 들어간다")
	assert_eq(inventory.get_slot(0)["count"], limit, "첫 슬롯은 스택 상한까지만 담긴다")
	assert_eq(inventory.get_slot(1)["count"], 2, "넘친 2개는 다음 슬롯으로 간다")
	assert_eq(inventory.used_slots(), 2, "두 슬롯을 써야 한다")

func test_partial_fill_tops_up_existing_stack_before_using_a_new_slot() -> void:
	var inventory: Inventory = _make_inventory()
	var limit: int = _stack_limit(&"bandage")

	inventory.add_item(&"bandage", limit - 1)
	inventory.add_item(&"bandage", 1)

	assert_eq(inventory.used_slots(), 1, "기존 스택을 먼저 채워야 새 슬롯을 낭비하지 않는다")
	assert_eq(inventory.get_slot(0)["count"], limit, "기존 스택이 상한까지 찼다")

## ★ 불변식: 슬롯 초과 금지. 16칸이 꽉 차면 더 받지 않는다.
func test_rejects_items_beyond_slot_capacity() -> void:
	var inventory: Inventory = _make_inventory()
	var limit: int = _stack_limit(&"bandage")
	var capacity: int = inventory.slot_count * limit

	var added_full: int = inventory.add_item(&"bandage", capacity)
	assert_eq(added_full, capacity, "정확히 가득 찰 만큼은 전부 들어간다")
	assert_eq(inventory.used_slots(), inventory.slot_count, "16칸이 모두 찼다")

	var overflow: int = inventory.add_item(&"bandage", 1)

	assert_eq(overflow, 0, "꽉 찬 인벤토리는 1개도 더 받지 않는다")
	assert_eq(inventory.count_of(&"bandage"), capacity, "보유량이 용량을 넘지 않는다")
	assert_eq(inventory.used_slots(), inventory.slot_count, "슬롯 수가 16 을 넘지 않는다")

func test_partial_add_when_only_some_room_left() -> void:
	var inventory: Inventory = _make_inventory()
	var limit: int = _stack_limit(&"bandage")
	var capacity: int = inventory.slot_count * limit
	inventory.add_item(&"bandage", capacity - 2)

	var added: int = inventory.add_item(&"bandage", 5)

	assert_eq(added, 2, "남은 자리만큼만 들어가야 한다")
	assert_eq(inventory.count_of(&"bandage"), capacity, "용량을 넘지 않는다")

## ★ 불변식: 음수 수량 금지.
func test_rejects_negative_and_zero_add() -> void:
	var inventory: Inventory = _make_inventory()
	inventory.add_item(&"stone", 4)

	assert_eq(inventory.add_item(&"stone", -3), 0, "음수 추가는 거부한다")
	assert_eq(inventory.add_item(&"stone", 0), 0, "0 개 추가는 아무것도 하지 않는다")
	assert_eq(inventory.count_of(&"stone"), 4, "거부된 요청이 보유량을 바꾸면 안 된다")

func test_rejects_negative_remove() -> void:
	var inventory: Inventory = _make_inventory()
	inventory.add_item(&"stone", 4)

	assert_false(inventory.remove_item(&"stone", -1), "음수 제거는 거부한다")
	assert_eq(inventory.count_of(&"stone"), 4, "거부된 요청이 보유량을 바꾸면 안 된다")

func test_count_never_goes_negative_on_over_remove() -> void:
	var inventory: Inventory = _make_inventory()
	inventory.add_item(&"stone", 2)

	assert_false(inventory.remove_item(&"stone", 5), "보유량보다 많이 빼는 것은 거부한다 (전부 아니면 전무)")
	assert_eq(inventory.count_of(&"stone"), 2, "실패한 제거는 보유량을 건드리지 않는다")

func test_remove_item_frees_the_slot_when_stack_empties() -> void:
	var inventory: Inventory = _make_inventory()
	inventory.add_item(&"stone", 3)

	assert_true(inventory.remove_item(&"stone", 3), "보유한 만큼은 뺄 수 있다")
	assert_eq(inventory.count_of(&"stone"), 0, "보유량이 0 이다")
	assert_eq(inventory.used_slots(), 0, "빈 스택은 슬롯을 반환해야 한다")

func test_remove_spans_multiple_stacks() -> void:
	var inventory: Inventory = _make_inventory()
	var limit: int = _stack_limit(&"bandage")
	inventory.add_item(&"bandage", limit + 2)

	assert_true(inventory.remove_item(&"bandage", limit + 1), "여러 스택에 걸쳐 뺄 수 있다")
	assert_eq(inventory.count_of(&"bandage"), 1, "1개가 남는다")
	assert_eq(inventory.used_slots(), 1, "빈 슬롯은 반환된다")

func test_unknown_item_is_rejected() -> void:
	var inventory: Inventory = _make_inventory()

	# GameData 에 없는 id. 조용한 기본값 대체 없이 거부되어야 한다 (설계서 13장).
	var added: int = inventory.add_item(&"plutonium", 1)

	assert_eq(added, 0, "등록되지 않은 아이템은 받지 않는다")
	assert_eq(inventory.used_slots(), 0, "슬롯을 소비하면 안 된다")
	assert_push_error("Missing item data", "누락된 데이터는 조용히 넘어가지 않고 에러를 내야 한다")

## 무게도 데이터에서 나온다 (UI 하드코딩 금지).
func test_total_weight_comes_from_item_data() -> void:
	var inventory: Inventory = _make_inventory()
	var stone_weight: float = _game_data.get_item(&"stone").weight
	var wood_weight: float = _game_data.get_item(&"wood").weight

	inventory.add_item(&"stone", 2)
	inventory.add_item(&"wood", 3)

	assert_almost_eq(inventory.total_weight(), stone_weight * 2.0 + wood_weight * 3.0, 0.001,
		"총 무게는 ItemData.weight 에서 계산되어야 한다")

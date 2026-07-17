extends GutTest

## 냄새 원천 아이템을 여러 개 들면 강도가 올라간다 (설계서 5.4).
## 기존 구현은 첫 번째 원천 하나만 등록해서 5개를 들어도 1개와 똑같았다.
##
## 합산 규칙 (Inventory.get_carried_smell 참조):
##   가장 강한 원천 1단위가 기준(base), 나머지 각 단위는 자기 강도의
##   ADDITIONAL_UNIT_FACTOR 만큼만 더한다. 총합은 base * MAX_MULTIPLIER 로 막는다.

const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")

var _game_data: Node = null

func before_each() -> void:
	_game_data = get_node("/root/GameData")

func _make_grid(authority: int = 1) -> SmellGrid:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	config.tick_interval = 0.25
	config.decay_factor = 1.0
	config.advect_fraction = 0.0
	config.min_active_value = 0.5
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2.ZERO
	grid.area_size = Vector2(1000.0, 1000.0)
	grid.set_multiplayer_authority(authority)
	add_child_autofree(grid)
	return grid

func _make_inventory(at: Vector2 = Vector2(250.0, 250.0)) -> Inventory:
	var body: Node2D = add_child_autofree(Node2D.new())
	body.global_position = at
	var inventory: Inventory = InventoryScript.new()
	body.add_child(inventory)
	return inventory


func test_no_smell_item_reports_empty() -> void:
	var inventory: Inventory = _make_inventory()

	assert_eq(inventory.add_item(&"stone", 3), 3, "전제: 냄새 없는 아이템만 보유")

	assert_true(inventory.get_carried_smell().is_empty(), "냄새 원천이 없으면 빈 결과여야 한다")


func test_single_unit_uses_item_strength_verbatim() -> void:
	var inventory: Inventory = _make_inventory()
	var meat: ItemData = _game_data.get_item(&"raw_meat")

	assert_eq(inventory.add_item(&"raw_meat", 1), 1)

	var smell: Dictionary = inventory.get_carried_smell()
	assert_almost_eq(float(smell["strength"]), meat.smell_strength, 0.01,
		"1개만 들면 리소스 강도 그대로여야 한다")
	assert_eq(smell["kind"], meat.get_smell_kind(), "냄새 종류는 리소스에서 온다")
	assert_almost_eq(float(smell["interval"]), meat.smell_interval_seconds, 0.01)


func test_strength_grows_with_carried_count() -> void:
	var inventory: Inventory = _make_inventory()

	assert_eq(inventory.add_item(&"raw_meat", 1), 1)
	var one: float = float(inventory.get_carried_smell()["strength"])

	assert_eq(inventory.add_item(&"raw_meat", 2), 2)
	var three: float = float(inventory.get_carried_smell()["strength"])

	assert_gt(three, one, "3개를 들면 1개보다 강해야 한다 (첫 원천만 등록하던 버그)")


func test_strength_follows_max_plus_bonus_rule() -> void:
	var inventory: Inventory = _make_inventory()
	var meat: ItemData = _game_data.get_item(&"raw_meat")

	assert_eq(inventory.add_item(&"raw_meat", 3), 3)

	var expected: float = meat.smell_strength \
		+ meat.smell_strength * 2.0 * InventoryScript.CARRIED_SMELL_ADDITIONAL_UNIT_FACTOR
	assert_almost_eq(float(inventory.get_carried_smell()["strength"]), expected, 0.01,
		"기준 강도 + 추가 단위 가산이어야 한다")


func test_strength_is_capped_so_a_stack_cannot_run_away() -> void:
	var inventory: Inventory = _make_inventory()
	var meat: ItemData = _game_data.get_item(&"raw_meat")
	var cap: float = meat.smell_strength * InventoryScript.CARRIED_SMELL_MAX_MULTIPLIER

	# 스택 상한을 넘겨 여러 슬롯에 걸치도록 넉넉히 넣는다.
	var added: int = inventory.add_item(&"raw_meat", meat.get_stack_limit() * 2)
	assert_gt(added, meat.get_stack_limit(), "전제: 두 슬롯 이상 차지한다")

	assert_almost_eq(float(inventory.get_carried_smell()["strength"]), cap, 0.01,
		"합산은 상한을 넘지 않는다")


## 같은 아이템이 슬롯 상한을 넘겨 여러 슬롯에 흩어져도 전량이 합산되어야 한다.
func test_counts_units_across_multiple_slots() -> void:
	var inventory: Inventory = _make_inventory()
	var meat: ItemData = _game_data.get_item(&"raw_meat")
	var over_one_slot: int = meat.get_stack_limit() + 1

	assert_eq(inventory.add_item(&"raw_meat", over_one_slot), over_one_slot)
	assert_gt(inventory.used_slots(), 1, "전제: 두 슬롯에 걸쳐 있다")

	var expected: float = meat.smell_strength \
		+ meat.smell_strength * float(over_one_slot - 1) * InventoryScript.CARRIED_SMELL_ADDITIONAL_UNIT_FACTOR
	expected = minf(expected, meat.smell_strength * InventoryScript.CARRIED_SMELL_MAX_MULTIPLIER)
	assert_almost_eq(float(inventory.get_carried_smell()["strength"]), expected, 0.01,
		"두 번째 슬롯의 수량도 합산에 들어가야 한다")


func test_removing_units_lowers_strength_back_down() -> void:
	var inventory: Inventory = _make_inventory()

	assert_eq(inventory.add_item(&"raw_meat", 3), 3)
	var three: float = float(inventory.get_carried_smell()["strength"])
	assert_true(inventory.remove_item(&"raw_meat", 2))
	var one: float = float(inventory.get_carried_smell()["strength"])

	assert_lt(one, three, "덜어내면 강도도 내려가야 한다")


func test_registered_source_strength_matches_aggregate() -> void:
	var grid: SmellGrid = _make_grid()
	var inventory: Inventory = _make_inventory()

	assert_eq(inventory.add_item(&"raw_meat", 3), 3)

	assert_eq(grid.get_registered_smell_source_count(), 1, "보유 원천은 하나로 합쳐 등록한다")
	assert_almost_eq(grid.get_registered_smell_strength(inventory),
		float(inventory.get_carried_smell()["strength"]), 0.01,
		"격자에 등록된 강도가 합산 결과와 같아야 한다")


func test_more_meat_emits_more_smell_into_the_grid() -> void:
	# 같은 격자 위 서로 다른 셀에 두 명을 세우고 실제로 쌓인 냄새를 비교한다.
	var grid: SmellGrid = _make_grid()
	var light_at: Vector2 = Vector2(150.0, 150.0)
	var heavy_at: Vector2 = Vector2(650.0, 650.0)
	var light: Inventory = _make_inventory(light_at)
	var heavy: Inventory = _make_inventory(heavy_at)

	assert_eq(light.add_item(&"raw_meat", 1), 1)
	assert_eq(heavy.add_item(&"raw_meat", 3), 3)
	assert_eq(grid.get_registered_smell_source_count(), 2, "전제: 두 보유 원천이 등록됐다")

	grid._process(0.5)

	var weak: float = grid.get_smell_at(light_at)
	var strong: float = grid.get_smell_at(heavy_at)
	assert_gt(weak, 0.0, "전제: 1개도 냄새를 낸다")
	assert_gt(strong, weak, "많이 들수록 격자에 더 진한 냄새가 쌓여야 한다")


func test_client_inventory_does_not_simulate_carried_smell() -> void:
	# 호스트 권위: 클라이언트 격자는 등록 원천을 자체 시뮬레이션하지 않는다.
	var grid: SmellGrid = _make_grid(2)
	var inventory: Inventory = _make_inventory()

	assert_eq(inventory.add_item(&"raw_meat", 3), 3)
	grid._process(0.5)

	assert_eq(grid.get_smell_at(Vector2(250.0, 250.0)), 0.0,
		"클라이언트는 보유 냄새를 스스로 만들지 않는다")

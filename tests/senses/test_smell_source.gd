extends GutTest

const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")
const SmellSourceScript = preload("res://scripts/senses/smell_source.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const WorldItemScript = preload("res://scripts/items/world_item.gd")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _make_config() -> SmellGridConfig:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	config.tick_interval = 0.25
	config.decay_factor = 1.0
	config.advect_fraction = 0.0
	config.min_active_value = 0.5
	return config

func _make_grid(authority: int = 1) -> SmellGrid:
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = _make_config()
	grid.area_origin = Vector2.ZERO
	grid.area_size = Vector2(1000.0, 1000.0)
	grid.set_multiplayer_authority(authority)
	add_child_autofree(grid)
	return grid

func test_floor_raw_meat_emits_smell_from_registered_source() -> void:
	var grid: SmellGrid = _make_grid()
	var item: WorldItem = WorldItemScript.new()
	item.item_id = &"raw_meat"
	item.count = 1
	item.global_position = Vector2(250.0, 250.0)
	add_child_autofree(item)
	# 등록은 한 프레임 지연된다 (씬 노드 순서에 기대지 않기 위해, smell_source.gd 참조).
	await wait_physics_frames(1)

	assert_eq(grid.get_registered_smell_source_count(), 1, "raw_meat 바닥 아이템은 냄새 원천으로 등록되어야 한다")

	grid._process(0.5)

	assert_gt(grid.get_smell_at(item.global_position), 0.0, "등록된 raw_meat 위치에서 주기적으로 냄새가 나야 한다")

## 순서 회귀: SmellGrid 는 자기 _ready 에서 smell_grid 그룹에 가입한다. 원천이 격자보다
## 먼저 준비되면(=main.tscn 의 실제 배치) _ready 시점엔 그룹이 비어 있다.
## 위 테스트들처럼 격자를 먼저 만들면 이 버그는 절대 재현되지 않는다.
func test_source_readied_before_the_grid_still_registers() -> void:
	var source: SmellSource = SmellSourceScript.new()
	source.kind = &"raw_meat"
	source.strength = 45.0
	source.interval_seconds = 0.5
	add_child_autofree(source)
	var grid: SmellGrid = _make_grid()

	await wait_physics_frames(1)

	assert_almost_eq(grid.get_registered_smell_strength(source), 45.0, 0.01,
		"원천이 격자보다 먼저 준비돼도 등록돼야 한다")


## 지연 등록의 함정: 등록되기 전에 해제되면(같은 프레임에 줍는 경우) 지연 호출이
## 뒤늦게 살려내면 안 된다.
func test_source_deactivated_before_registration_never_registers() -> void:
	var source: SmellSource = SmellSourceScript.new()
	source.kind = &"raw_meat"
	source.strength = 45.0
	add_child_autofree(source)
	var grid: SmellGrid = _make_grid()

	source.deactivate()
	await wait_physics_frames(1)

	assert_eq(grid.get_registered_smell_source_count(), 0,
		"등록 전에 해제된 원천이 지연 호출로 되살아나면 안 된다")


func test_pickup_unregisters_floor_source_and_registers_carried_source() -> void:
	var grid: SmellGrid = _make_grid()
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var item: WorldItem = WorldItemScript.new()
	item.item_id = &"raw_meat"
	item.count = 1
	item.global_position = Vector2(250.0, 250.0)
	add_child_autofree(item)
	await wait_physics_frames(1)
	assert_eq(grid.get_registered_smell_source_count(), 1, "전제: 바닥 원천 1개")

	player.global_position = Vector2(650.0, 250.0)
	item.apply_pickup(player)
	grid._process(0.5)

	assert_eq(grid.get_registered_smell_source_count(), 1, "줍고 나면 바닥 원천은 해제되고 보유 원천만 남아야 한다")
	assert_eq(grid.get_smell_at(Vector2(250.0, 250.0)), 0.0, "주운 뒤에는 바닥 위치에서 새 냄새가 나면 안 된다")
	assert_gt(grid.get_smell_at(player.global_position), 0.0, "들고 있는 플레이어 위치에서 냄새가 나야 한다")

func test_carried_smell_unregisters_when_raw_meat_removed() -> void:
	var grid: SmellGrid = _make_grid()
	var player: Node2D = add_child_autofree(Node2D.new())
	var inventory: Inventory = InventoryScript.new()
	player.add_child(inventory)

	assert_eq(inventory.add_item(&"raw_meat", 1), 1)
	assert_eq(grid.get_registered_smell_source_count(), 1)

	assert_true(inventory.remove_item(&"raw_meat", 1))

	assert_eq(grid.get_registered_smell_source_count(), 0, "raw_meat 이 없어지면 보유 냄새 원천을 해제해야 한다")

func test_non_authority_grid_does_not_emit_registered_sources() -> void:
	var grid: SmellGrid = _make_grid(2)
	var source: SmellSource = SmellSourceScript.new()
	source.kind = &"raw_meat"
	source.strength = 50.0
	source.interval_seconds = 0.5
	source.global_position = Vector2(250.0, 250.0)
	add_child_autofree(source)

	grid._process(0.5)

	assert_eq(grid.get_smell_at(source.global_position), 0.0, "클라이언트 격자는 등록 원천을 자체 시뮬레이션하지 않는다")

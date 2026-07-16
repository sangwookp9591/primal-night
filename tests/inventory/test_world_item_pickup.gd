extends GutTest

## 월드에 떨어진 아이템을 상호작용으로 줍는다 -> EventBus.item_picked_up.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

## Area2D 겹침은 물리 프레임이 지나야 반영된다.
func _spawn(item_id: StringName, count: int, offset: Vector2) -> Array:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var item: WorldItem = WorldItemScene.instantiate()
	item.item_id = item_id
	item.count = count
	item.position = offset
	world.add_child(item)
	await wait_physics_frames(2)
	return [player, item]

func test_interactor_finds_the_nearby_world_item() -> void:
	var spawned: Array = await _spawn(&"stone", 3, Vector2(16.0, 0.0))
	var player: Player = spawned[0]

	assert_eq(player.interactor.find_target(), spawned[1], "사거리 안의 아이템을 찾아야 한다")

func test_far_item_is_not_found() -> void:
	var spawned: Array = await _spawn(&"stone", 3, Vector2(400.0, 0.0))
	var player: Player = spawned[0]

	assert_null(player.interactor.find_target(), "사거리 밖 아이템은 잡히면 안 된다")

func test_pickup_adds_to_inventory_and_emits_item_picked_up() -> void:
	var spawned: Array = await _spawn(&"stone", 3, Vector2(16.0, 0.0))
	var player: Player = spawned[0]
	var item: WorldItem = spawned[1]
	watch_signals(_event_bus)

	player.interactor.begin()

	assert_eq(player.inventory.count_of(&"stone"), 3, "돌 3개가 인벤토리에 들어가야 한다")
	assert_signal_emitted(_event_bus, "item_picked_up", "item_picked_up 이 발신되어야 한다")
	var params: Array = get_signal_parameters(_event_bus, "item_picked_up", 0)
	assert_eq(params[0], &"stone", "주운 아이템 id 가 전달되어야 한다")
	assert_eq(params[1], player, "주운 주체가 전달되어야 한다")
	assert_true(item.is_queued_for_deletion(), "주운 아이템은 월드에서 사라져야 한다")

func test_pickup_is_instant_not_hold() -> void:
	var spawned: Array = await _spawn(&"wood", 1, Vector2(16.0, 0.0))
	var item: WorldItem = spawned[1]

	assert_eq(item.get_hold_seconds(), 0.0, "줍기는 길게 누르지 않는다")

## 인벤토리가 꽉 차면 줍지 못하고 아이템은 월드에 남는다 (불변식이 상호작용까지 이어진다).
func test_pickup_rejected_when_inventory_is_full() -> void:
	var spawned: Array = await _spawn(&"stone", 1, Vector2(16.0, 0.0))
	var player: Player = spawned[0]
	var item: WorldItem = spawned[1]
	var limit: int = player.inventory.slot_count * 5  # 붕대 스택 상한 5
	player.inventory.add_item(&"bandage", limit)
	assert_eq(player.inventory.used_slots(), 16, "16칸이 모두 찼다")

	player.interactor.begin()

	assert_eq(player.inventory.count_of(&"stone"), 0, "자리가 없으면 줍지 못한다")
	assert_false(item.is_queued_for_deletion(), "줍지 못한 아이템은 월드에 남아야 한다")

## 일부만 들어가면 들어간 만큼만 줄이고 나머지는 월드에 남긴다 (아이템 복제/소실 금지).
func test_partial_pickup_leaves_the_remainder_in_the_world() -> void:
	var spawned: Array = await _spawn(&"bandage", 4, Vector2(16.0, 0.0))
	var player: Player = spawned[0]
	var item: WorldItem = spawned[1]
	# 16칸 * 5 = 80 이 용량. 78개를 채워 2자리만 남긴다.
	player.inventory.add_item(&"bandage", 78)

	player.interactor.begin()

	assert_eq(player.inventory.count_of(&"bandage"), 80, "남은 2자리만 채운다")
	assert_false(item.is_queued_for_deletion(), "남은 아이템은 사라지면 안 된다")
	assert_eq(item.count, 2, "월드 아이템 수량이 주운 만큼 줄어야 한다")

extends GutTest

const CampfireRegistryScript = preload("res://scripts/props/campfire_registry.gd")

var _registry: Node = null


func before_each() -> void:
	_registry = CampfireRegistryScript.new()
	add_child_autofree(_registry)


func test_registering_the_same_fire_twice_is_idempotent() -> void:
	var fire: Node2D = add_child_autofree(Node2D.new())
	_registry.register_fire(fire, Vector2(20.0, 0.0), 100.0)
	_registry.register_fire(fire, Vector2(20.0, 0.0), 100.0)

	assert_eq(_registry.get_active_fires().size(), 1)
	assert_eq(_registry.nearest_fire(Vector2.ZERO).node, fire)
	assert_true(_registry.is_position_protected(Vector2.ZERO))


func test_freed_fire_is_pruned_from_all_queries() -> void:
	var fire: Node2D = Node2D.new()
	add_child(fire)
	_registry.register_fire(fire, Vector2.ZERO, 100.0)

	fire.queue_free()
	await wait_process_frames(1)

	assert_true(_registry.get_active_fires().is_empty())
	assert_true(_registry.nearest_fire(Vector2.ZERO).is_empty())
	assert_false(_registry.is_position_protected(Vector2.ZERO))


func test_extinguish_and_tree_removal_are_safe_in_either_order() -> void:
	var extinguished_first: Node2D = Node2D.new()
	add_child(extinguished_first)
	_registry.register_fire(extinguished_first, Vector2.ZERO, 100.0)
	_registry.unregister_fire(extinguished_first)
	extinguished_first.queue_free()

	var freed_first: Node2D = Node2D.new()
	add_child(freed_first)
	_registry.register_fire(freed_first, Vector2.ZERO, 100.0)
	freed_first.queue_free()
	await wait_process_frames(1)
	_registry.unregister_fire(freed_first)

	assert_true(_registry.get_active_fires().is_empty())


func test_late_consumer_can_read_an_existing_fire() -> void:
	var fire: Node2D = add_child_autofree(Node2D.new())
	_registry.register_fire(fire, Vector2(300.0, 0.0), 80.0)

	# 소비자는 등록 시점에 구독하지 않아도 현재 스냅샷을 바로 읽는다.
	var active_fires: Array[Dictionary] = _registry.get_active_fires()
	assert_eq(active_fires.size(), 1)
	assert_eq(active_fires[0].position, Vector2(300.0, 0.0))
	assert_true(_registry.is_position_protected(Vector2(350.0, 0.0)))

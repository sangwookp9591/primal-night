extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

class Target:
	extends Area2D

	var interact_count: int = 0

	func _init() -> void:
		collision_layer = 4
		collision_mask = 0
		monitoring = false
		var collision := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		collision.shape = circle
		add_child(collision)

	func can_interact(_who: Node) -> bool:
		return true

	func get_hold_seconds() -> float:
		return 0.0

	func get_prompt() -> String:
		return name

	func interact(_who: Node) -> void:
		interact_count += 1

func _spawn_targets() -> Array:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var far := Target.new()
	far.name = "Far"
	far.position = Vector2(40.0, 0.0)
	world.add_child(far)
	var near := Target.new()
	near.name = "Near"
	near.position = Vector2(16.0, 0.0)
	world.add_child(near)
	await wait_physics_frames(2)
	return [player, near, far]

func test_candidates_are_sorted_nearest_first() -> void:
	var spawned: Array = await _spawn_targets()
	var interactor: Interactor = (spawned[0] as Player).interactor

	assert_eq(interactor.sorted_candidates(), [spawned[1], spawned[2]])
	assert_eq(interactor.find_target(), spawned[1])

func test_cycle_advances_and_wraps_in_distance_order() -> void:
	var spawned: Array = await _spawn_targets()
	var interactor: Interactor = (spawned[0] as Player).interactor

	interactor.find_target()
	interactor.cycle_target()
	assert_eq(interactor.current_target, spawned[2])
	interactor.cycle_target()
	assert_eq(interactor.current_target, spawned[1])

func test_interact_uses_the_cycled_target() -> void:
	var spawned: Array = await _spawn_targets()
	var player: Player = spawned[0]
	var near: Target = spawned[1]
	var far: Target = spawned[2]

	player.interactor.cycle_target()
	player.interactor.begin()

	assert_eq(near.interact_count, 0)
	assert_eq(far.interact_count, 1)

func test_candidate_leaving_radius_resets_cycle_to_nearest() -> void:
	var spawned: Array = await _spawn_targets()
	var player: Player = spawned[0]
	var near: Target = spawned[1]
	var far: Target = spawned[2]
	player.interactor.find_target()
	player.interactor.cycle_target()
	assert_eq(player.interactor.current_target, far)

	far.position = Vector2(200.0, 0.0)
	await wait_physics_frames(2)

	assert_eq(player.interactor.current_target, near)

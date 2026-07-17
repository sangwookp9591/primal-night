extends GutTest

const RaptorScript = preload("res://scripts/creature/raptor.gd")
const PackCoordinatorScript = preload("res://scripts/creature/pack_coordinator.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")

var _event_bus: Node = null


func before_each() -> void:
	_event_bus = get_node("/root/EventBus")


func _make_data() -> CreatureData:
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 120.0
	data.lose_sight_radius = 240.0
	data.smell_threshold = 8.0
	data.investigate_arrive_distance = 24.0
	data.occlusion_attenuation = 1.0
	data.search_sweeps = 2
	return data


func _spawn_raptor(at: Vector2) -> Raptor:
	var raptor: Raptor = RaptorScript.new()
	raptor.data = _make_data()
	raptor.position = at
	add_child_autofree(raptor)
	return raptor


func _spawn_player(at: Vector2) -> Node2D:
	var player := Node2D.new()
	player.add_to_group(&"player")
	player.position = at
	add_child_autofree(player)
	return player


func _spawn_pack() -> Node:
	var pack: Node = PackCoordinatorScript.new()
	add_child_autofree(pack)
	return pack


func test_pack_assigns_different_flanking_targets_for_same_noise_cue() -> void:
	_spawn_pack()
	var left: Raptor = _spawn_raptor(Vector2.ZERO)
	var right: Raptor = _spawn_raptor(Vector2(0.0, 40.0))
	var cue := Vector2(300.0, 0.0)

	_event_bus.noise_emitted.emit(cue, 400.0, null)
	await wait_physics_frames(2)
	left._ai_tick()
	right._ai_tick()

	assert_eq(left.state, Raptor.State.INVESTIGATE)
	assert_eq(right.state, Raptor.State.INVESTIGATE)
	assert_ne(left.move_target, cue, "pack member should approach the cue from a side")
	assert_ne(right.move_target, cue, "pack member should approach the cue from the opposite side")
	assert_gt(left.move_target.distance_to(right.move_target), 100.0,
		"two raptors should not stack on the same investigation point")


func test_without_pack_coordinator_single_raptor_keeps_existing_noise_target() -> void:
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	var cue := Vector2(300.0, 0.0)

	_event_bus.noise_emitted.emit(cue, 400.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE)
	assert_eq(raptor.move_target, cue,
		"without pack coordination, existing single-raptor investigation behavior remains exact")


func test_pack_prefers_isolated_visible_player_over_nearest_clustered_target() -> void:
	_spawn_pack()
	var first: Raptor = _spawn_raptor(Vector2.ZERO)
	_spawn_raptor(Vector2(-20.0, 0.0))
	_spawn_player(Vector2(40.0, 0.0))
	_spawn_player(Vector2(45.0, 8.0))
	var isolated: Node2D = _spawn_player(Vector2(95.0, 0.0))

	first._ai_tick()

	assert_eq(first.state, Raptor.State.CHASE)
	assert_eq(first.move_target, isolated.global_position,
		"with pack coordination, isolated prey is a better target than a nearby clustered player")


func test_pack_search_does_not_follow_live_player_position() -> void:
	_spawn_pack()
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	_spawn_raptor(Vector2(0.0, 40.0))
	var player: Node2D = _spawn_player(Vector2(300.0, 0.0))
	var heard := player.global_position

	_event_bus.noise_emitted.emit(heard, 400.0, player)
	await wait_physics_frames(2)
	raptor._ai_tick()
	var assigned: Vector2 = raptor.move_target

	player.global_position = Vector2(-900.0, 500.0)
	raptor.global_position = assigned
	raptor._ai_tick()

	assert_ne(raptor.move_target, player.global_position,
		"pack investigation uses the heard cue and sweep rng, not live player coordinates")
	assert_lte(raptor.move_target.distance_to(assigned), raptor.data.search_radius,
		"sweep remains around the assigned flank target")

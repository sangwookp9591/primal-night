extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CampfireScene: PackedScene = preload("res://scenes/props/campfire.tscn")
const CampfireSiteScene: PackedScene = preload("res://scenes/props/campfire_site.tscn")
const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")


func before_each() -> void:
	get_node("/root/CampfireRegistry").clear_for_test()


func _player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_wet_fuel_switches_on_visible_smoke_and_larger_lure() -> void:
	var fire: Campfire = CampfireScene.instantiate()
	add_child_autofree(fire)
	fire.light()
	var heard: Array[float] = []
	var bus := get_node("/root/EventBus")
	bus.noise_emitted.connect(
		func(_position: Vector2, radius: float, _source: Node) -> void: heard.append(radius),
		CONNECT_ONE_SHOT)
	assert_true(fire.add_fuel(true))
	assert_true(fire.smoky)
	assert_true(fire.get_node("SmokeColumn").visible)
	assert_eq(heard, [Campfire.SMOKE_LURE_RADIUS])
	fire.set_smoky(false)
	assert_false(fire.smoky)


func test_fuel_exhaustion_leaves_one_collectible_charcoal() -> void:
	var player := _player()
	var site: CampfireSite = CampfireSiteScene.instantiate()
	add_child_autofree(site)
	site.build_and_light()
	site.campfire.extinguish(true)
	assert_eq(site.cook_kind(player), &"charcoal")
	assert_true(site.apply_cook(player))
	assert_eq(player.inventory.count_of(&"charcoal"), 1)
	assert_false(site.campfire.charcoal_available)
	assert_false(site.apply_cook(player))


func test_charcoal_masks_smell_for_three_minutes_and_blocks_fire_warmth() -> void:
	var player := _player()
	player.inventory.add_item(&"charcoal", 1)
	player.stats.temperature = 50.0
	assert_true(player.stats.try_use_charcoal())
	assert_eq(player.stats.charcoal_mask_remaining, 180.0)
	assert_eq(player.stats.charcoal_smell_multiplier(), 0.15)
	var before := player.stats.temperature
	player.stats.simulate(1.0)
	assert_lte(player.stats.temperature, before)
	player.stats.wash_charcoal_mask()
	assert_eq(player.stats.charcoal_mask_remaining, 0.0)
	assert_eq(player.stats.charcoal_smell_multiplier(), 1.0)


func test_oil_trap_installs_ignites_hurts_player_and_registers_fire_barrier() -> void:
	var player := _player()
	player.inventory.add_item(&"oil_trap", 1)
	var root: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var trap := OilTrap.install(root, player, Vector2(20.0, 0.0))
	assert_not_null(trap)
	assert_eq(player.inventory.count_of(&"oil_trap"), 0)
	var fire: Campfire = CampfireScene.instantiate()
	fire.position = trap.position
	root.add_child(fire)
	fire.light()
	assert_true(trap.ignite())
	assert_true(trap.ignited)
	var registry := get_node("/root/CampfireRegistry")
	assert_true(registry.is_position_protected(trap.global_position))
	var health_before := player.health.current_health
	trap.apply_flame_damage(player, 1.0)
	assert_eq(player.health.current_health, health_before - OilTrap.DAMAGE_PER_SECOND)
	trap.extinguish()
	assert_false(trap.ignited)


func test_new_item_atlas_cells_are_fixed_through_twenty_nine() -> void:
	assert_eq(WorldItem.ITEM_SHEET.get_width(), 1856)
	assert_eq(WorldItem.atlas_index_for(&"charcoal"), 25)
	assert_eq(WorldItem.atlas_index_for(&"oil_trap"), 26)
	assert_eq(WorldItem.atlas_index_for(&"snare_kit"), 27)
	assert_eq(WorldItem.atlas_index_for(&"shelter_kit"), 28)


func test_burning_oil_uses_existing_fire_contract_to_force_raptor_retreat() -> void:
	var root: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var trap := OilTrap.new()
	root.add_child(trap)
	var ignition: Campfire = CampfireScene.instantiate()
	root.add_child(ignition)
	ignition.light()
	assert_true(trap.ignite())
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 300.0
	data.lose_sight_radius = 500.0
	data.fire_exit_ratio = 1.3
	var raptor: Raptor = RaptorScript.new()
	raptor.data = data
	raptor.position = Vector2(24.0, 0.0)
	root.add_child(raptor)
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.FLEE)
	assert_gt(raptor.move_target.distance_to(trap.global_position), OilTrap.FIRE_RADIUS)

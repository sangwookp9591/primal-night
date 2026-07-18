extends GutTest

const RaptorScene: PackedScene = preload("res://scenes/creature/raptor.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")

func test_melee_arc_respects_range_arc_and_eight_direction_snap() -> void:
	assert_true(NetCombat.is_in_melee_arc(Vector2(100, 0), Vector2.RIGHT, 112.0, 24.0))
	assert_false(NetCombat.is_in_melee_arc(Vector2(113, 0), Vector2.RIGHT, 112.0, 24.0))
	assert_false(NetCombat.is_in_melee_arc(Vector2(80, 80), Vector2.RIGHT, 112.0, 24.0))
	assert_true(NetCombat.is_in_melee_arc(Vector2(40, 40), Vector2.RIGHT, 62.0, 52.0))
	assert_almost_eq(NetCombat.snap_direction_8(Vector2(0.8, -0.7)),
		Vector2(1, -1).normalized(), Vector2(0.001, 0.001))

func test_stamina_spend_rejects_when_insufficient() -> void:
	var stamina: StaminaComponent = autofree(StaminaComponent.new())
	stamina.current_stamina = 20.0
	assert_true(stamina.try_spend(18.0))
	assert_eq(stamina.current_stamina, 2.0)
	assert_false(stamina.try_spend(18.0))
	assert_eq(stamina.current_stamina, 2.0)

func test_raptor_damage_flee_death_and_carcass_spawn() -> void:
	var arena: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var raptor := RaptorScene.instantiate() as Raptor
	raptor.name = "CombatRaptor"
	arena.add_child(raptor)
	var attacker := Node2D.new()
	attacker.position = Vector2(-20, 0)
	arena.add_child(attacker)
	var start_health := raptor.current_health
	assert_true(raptor.take_damage(10.0, Vector2.RIGHT, attacker))
	assert_eq(raptor.current_health, start_health - 10.0)
	assert_eq(raptor.state, Raptor.State.FLEE)
	assert_true(raptor.take_damage(raptor.current_health, Vector2.RIGHT, attacker))
	assert_true(raptor.is_dead())
	assert_not_null(arena.get_node_or_null("CombatRaptorCarcass"))
	await wait_process_frames(1)
	assert_null(arena.get_node_or_null("CombatRaptor"))

func test_client_side_raptor_cannot_mutate_authoritative_health() -> void:
	var raptor := RaptorScene.instantiate() as Raptor
	raptor.set_multiplayer_authority(2)
	add_child_autofree(raptor)
	var before := raptor.current_health
	assert_false(raptor.take_damage(999.0, Vector2.RIGHT))
	assert_eq(raptor.current_health, before)

func test_weapon_catalog_and_recipe_contract() -> void:
	var game_data := get_node("/root/GameData")
	var spear := game_data.get_item(&"stone_spear") as WearableData
	var knife := game_data.get_item(&"stone_knife") as WearableData
	assert_not_null(spear)
	assert_not_null(knife)
	assert_eq(spear.equip_slot, &"main_hand")
	assert_eq(knife.equip_slot, &"main_hand")
	assert_eq(spear.visual_id, &"stone_spear")
	assert_not_null(game_data.get_recipe(&"craft_stone_spear"))

func test_weapon_requirement_cooldown_stamina_and_noise() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate()) as Node2D
	var player: Player = main.get_node("Player")
	var combat: NetCombat = main.get_node("NetCombat")
	var bus := get_node("/root/EventBus")
	watch_signals(bus)
	assert_false(combat.request_attack(player, Vector2.RIGHT), "비무장 공격은 거부한다")
	player.inventory.add_item(&"stone_spear", 1)
	assert_true(player.equipment.request_equip(&"stone_spear"))
	var before := player.stamina.current_stamina
	assert_true(combat.request_attack(player, Vector2.RIGHT))
	assert_eq(player.stamina.current_stamina, before - NetCombat.ATTACK_STAMINA)
	assert_signal_emit_count(bus, "noise_emitted", 1)
	assert_false(combat.request_attack(player, Vector2.RIGHT), "쿨다운 안의 연속 공격은 거부한다")
	assert_eq(player.stamina.current_stamina, before - NetCombat.ATTACK_STAMINA,
		"거부된 공격은 스태미나를 더 쓰지 않는다")

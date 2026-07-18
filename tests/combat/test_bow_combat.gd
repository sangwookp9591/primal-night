extends GutTest

const MainScene: PackedScene = preload("res://scenes/main.tscn")

func _equip_bow(player: Player, arrows: int) -> void:
	assert_eq(player.inventory.add_item(&"bow", 1), 1)
	assert_true(player.equipment.request_equip(&"bow"))
	if arrows > 0:
		assert_eq(player.inventory.add_item(&"arrow", arrows), arrows)

func test_bow_catalog_recipe_and_placeholder_contract() -> void:
	var game_data := get_node("/root/GameData")
	var bow := game_data.get_item(&"bow") as WearableData
	var arrow := game_data.get_item(&"arrow") as ItemData
	assert_not_null(bow)
	assert_not_null(arrow)
	assert_eq(bow.equip_slot, &"main_hand")
	assert_eq(bow.visual_id, &"bow")
	assert_true(arrow.stackable)
	assert_eq(game_data.get_recipe(&"craft_arrow").result_count, 5)
	assert_not_null(game_data.get_recipe(&"craft_bow"))
	assert_true(PlayerVisualProfile.has_complete_frame_keys(&"bow"))

func test_aim_fire_state_transition_ammo_consumption_and_empty_rejection() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate()) as Node2D
	var player: Player = main.get_node("Player")
	var combat: NetCombat = main.get_node("NetCombat")
	_equip_bow(player, 1)
	assert_true(combat.request_bow_aim(player, true, Vector2.RIGHT))
	assert_true(player.bow_aiming)
	assert_true(combat.request_bow_fire(player, Vector2.RIGHT))
	assert_false(player.bow_aiming)
	assert_eq(player.inventory.count_of(&"arrow"), 0)
	await wait_seconds(NetCombat.BOW_RELOAD_SECONDS + 0.1)
	assert_true(combat.request_bow_aim(player, true, Vector2.RIGHT))
	assert_false(combat.request_bow_fire(player, Vector2.RIGHT), "소진 시 발사할 수 없다")
	assert_false(player.bow_aiming)

func test_projectile_hit_damage_range_end_and_recovery_drop() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate()) as Node2D
	var player: Player = main.get_node("Player")
	var raptor: Raptor = main.get_node("Raptor")
	var combat: NetCombat = main.get_node("NetCombat")
	raptor.set_physics_process(false)
	raptor.global_position = player.global_position + Vector2(240, 0)
	_equip_bow(player, 2)
	var before := raptor.current_health
	assert_true(combat.request_bow_aim(player, true, Vector2.RIGHT))
	assert_true(combat.request_bow_fire(player, Vector2.RIGHT))
	await wait_seconds(0.5)
	assert_eq(raptor.current_health, before - NetCombat.BOW_DAMAGE)
	assert_not_null(main.get_node_or_null("RecoveredArrow1"), "명중 지점 화살 회수 드롭")
	await wait_seconds(NetCombat.BOW_RELOAD_SECONDS + 0.1)
	raptor.global_position = player.global_position + Vector2(0, 400)
	assert_true(combat.request_bow_aim(player, true, Vector2.RIGHT))
	assert_true(combat.request_bow_fire(player, Vector2.RIGHT))
	await wait_seconds(0.9)
	var miss := main.get_node_or_null("RecoveredArrow2") as WorldItem
	assert_not_null(miss, "최대 사거리 종료 화살 회수 드롭")
	assert_almost_eq(miss.global_position.distance_to(player.global_position),
		NetCombat.BOW_RANGE, 2.0)

func test_spear_and_bow_tradeoff_is_not_linear_dps_upgrade() -> void:
	assert_gt(NetCombat.BOW_RANGE, NetCombat.SPEAR_RANGE * 4.0,
		"활은 선제 거리 우위")
	assert_lt(NetCombat.BOW_DAMAGE, NetCombat.SPEAR_DAMAGE,
		"활 단발 피해는 창보다 낮다")
	assert_gt(NetCombat.BOW_RELOAD_SECONDS, NetCombat.ATTACK_COOLDOWN,
		"근거리 급습의 연속 DPS는 창 우위")
	assert_lt(NetCombat.BOW_AIM_MOVE_MULTIPLIER, 0.5,
		"활은 조준 중 이동 제약")

func test_forged_bow_owner_claim_is_rejected() -> void:
	var main: Node2D = add_child_autofree(MainScene.instantiate()) as Node2D
	var combat: NetCombat = main.get_node("NetCombat")
	var before := combat.get_rejection_count()
	combat.submit_bow_fire_intent("forged-player", Vector2.RIGHT)
	assert_gt(combat.get_rejection_count(), before)

extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func test_player_has_code_created_injury_component() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())

	assert_not_null(player.get_node_or_null("InjuryComponent"),
		"Player 가 InjuryComponent 를 코드로 붙여야 한다")


func test_body_part_identifier_accepts_exactly_four_parts() -> void:
	var injury: InjuryComponent = add_child_autofree(InjuryComponent.new())

	for part: StringName in [&"head", &"torso", &"arm", &"leg"]:
		assert_true(injury.is_valid_body_part(part), "%s 부위를 허용해야 한다" % part)
	assert_false(injury.is_valid_body_part(&"tail"), "미등록 부위를 거부해야 한다")
	assert_false(injury.is_valid_body_part(&""), "빈 부위를 거부해야 한다")


func test_only_leg_laceration_is_an_active_injury() -> void:
	var injury: InjuryComponent = add_child_autofree(InjuryComponent.new())

	assert_false(injury.apply_replicated(&"head", &"laceration"),
		"머리 열상은 W6 활성 범위가 아니다")
	assert_true(injury.apply_replicated(&"leg", &"laceration"))
	assert_true(injury.has_leg_laceration())
	assert_lt(injury.movement_multiplier(), 1.0, "다리 열상만 이동 효율을 낮춰야 한다")


func test_zero_damage_leg_laceration_does_not_kill() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var before: float = player.health.current_health

	assert_true(player.injury.apply_host_leg_laceration(0.0))
	assert_true(player.health.is_alive(), "피해 수치가 0이어도 즉사시키면 안 된다")
	assert_eq(player.health.current_health, before)
	assert_true(player.health.is_bleeding, "다리 열상은 출혈과 연결되어야 한다")


func test_clear_removes_body_part_state_and_movement_effect() -> void:
	var injury: InjuryComponent = add_child_autofree(InjuryComponent.new())
	injury.apply_replicated(&"leg", &"laceration")

	injury.clear()

	assert_eq(injury.body_part, &"")
	assert_eq(injury.injury_kind, &"")
	assert_eq(injury.movement_multiplier(), 1.0)

extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")

class FakeNetCombat extends Node:
	var attack_requests: int = 0

	func _ready() -> void:
		add_to_group(&"net_combat")

	func request_attack(_player: Player, _direction: Vector2) -> void:
		attack_requests += 1


func before_each() -> void:
	Input.action_release("move_right")
	Input.action_release("crouch")


func after_each() -> void:
	Input.action_release("move_right")
	Input.action_release("crouch")


func _make_pair() -> Dictionary:
	var player := add_child_autofree(PlayerScene.instantiate()) as Player
	var carcass := add_child_autofree(CarcassScene.instantiate()) as Carcass
	player.global_position = Vector2.ZERO
	carcass.global_position = Vector2(20.0, 0.0)
	return {player = player, carcass = carcass}


func test_drag_reduces_speed_and_carcass_follows_then_drops() -> void:
	var pair := _make_pair()
	var player: Player = pair.player
	var carcass: Carcass = pair.carcass
	assert_true(carcass.toggle_drag_authoritative(player))
	Input.action_press("move_right")
	await wait_physics_frames(2)
	assert_almost_eq(player.velocity.length(), player.config.walk_speed * 0.6, 0.5)

	var before := carcass.global_position
	player.global_position = Vector2(80.0, 0.0)
	carcass._process(0.2)
	assert_gt(carcass.global_position.distance_to(before), 0.0, "사체가 플레이어를 따라가야 한다")
	assert_true(carcass.toggle_drag_authoritative(player), "다시 상호작용하면 놓는다")
	assert_null(player.dragged_carcass)
	assert_null(carcass.dragged_by)


func test_crouch_interact_toggles_drag_without_replacing_butcher_hold() -> void:
	var pair := _make_pair()
	var player: Player = pair.player
	var carcass: Carcass = pair.carcass
	Input.action_press("crouch")
	assert_true(carcass.can_interact(player))
	assert_eq(carcass.get_hold_seconds(), 0.0)
	assert_eq(carcass.get_prompt(), "사체 끌기")
	carcass.interact(player)
	assert_eq(carcass.dragged_by, player)
	assert_eq(carcass.get_prompt(), "사체 놓기")
	carcass.interact(player)
	assert_null(carcass.dragged_by)


func test_drag_emits_blood_trail_and_damage_forces_release() -> void:
	var pair := _make_pair()
	var player: Player = pair.player
	var carcass: Carcass = pair.carcass
	assert_true(carcass.toggle_drag_authoritative(player))
	player.global_position = Vector2(100.0, 0.0)
	carcass._process(Carcass.DRAG_TRAIL_INTERVAL_SECONDS + 0.01)
	var trail := player.get_node("BloodTrail") as BloodTrail
	assert_gt(trail.drops.size(), 0, "끄는 동안 피 냄새 방울이 남아야 한다")

	player.health.take_damage(1.0, &"claw")
	assert_null(carcass.dragged_by, "피격 시 사체를 즉시 놓아야 한다")
	assert_null(player.dragged_carcass)


func test_drag_blocks_attack_request() -> void:
	var pair := _make_pair()
	var player: Player = pair.player
	var carcass: Carcass = pair.carcass
	var combat: FakeNetCombat = add_child_autofree(FakeNetCombat.new()) as FakeNetCombat
	assert_true(carcass.toggle_drag_authoritative(player))
	player._request_attack()
	assert_eq(combat.attack_requests, 0, "손이 막힌 끌기 상태에서는 공격 경로가 열리면 안 된다")


func test_final_butcher_stage_grants_tallow() -> void:
	var pair := _make_pair()
	var player: Player = pair.player
	var carcass: Carcass = pair.carcass
	for _stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.apply_stage(player))
	assert_eq(player.inventory.count_of(&"tallow"), 1,
		"완전 해체 산출에 동물 지방 1개가 포함돼야 한다")

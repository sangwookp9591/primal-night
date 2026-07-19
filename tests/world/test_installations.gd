extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const SnareScene: PackedScene = preload("res://scenes/world/snare_trap.tscn")
const ShelterScene: PackedScene = preload("res://scenes/world/field_shelter.tscn")
const ScavengerScene: PackedScene = preload("res://scenes/creature/scavenger.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const TEST_SAVE: String = "user://test_installations.save"


func before_each() -> void:
	SaveService.pending_snapshot = {}
	SaveService.launch_requested = false
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func after_each() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(TEST_SAVE)


func test_recipe_costs_match_fixed_contract() -> void:
	var snare: RecipeData = get_node("/root/GameData").get_recipe(&"craft_snare_kit")
	var shelter: RecipeData = get_node("/root/GameData").get_recipe(&"craft_shelter_kit")
	assert_eq(snare.ingredients, {&"fiber": 2, &"wood": 1})
	assert_eq(shelter.ingredients, {&"hide": 2, &"wood": 2})


func test_install_consumes_kit_and_places_requested_node() -> void:
	var root: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var player := PlayerScene.instantiate() as Player
	root.add_child(player)
	var manager := WorldInstallations.new()
	root.add_child(manager)
	player.inventory.add_item(&"snare_kit", 1)
	var placed := manager.request_place(player, &"snare_kit")
	assert_true(placed is SnareTrap)
	assert_eq(player.inventory.count_of(&"snare_kit"), 0)


func test_seeded_snare_capture_recovery_and_spoil_smell() -> void:
	var player := add_child_autofree(PlayerScene.instantiate()) as Player
	var trap := add_child_autofree(SnareScene.instantiate()) as SnareTrap
	var scavenger := add_child_autofree(ScavengerScene.instantiate()) as Scavenger
	trap.capture_chance = 0.65
	trap.global_position = Vector2.ZERO
	scavenger.global_position = Vector2.ZERO
	assert_true(trap.attempt_capture(scavenger, 0.25), "결정적 성공 roll은 포획돼야 한다")
	assert_eq(trap.state, SnareTrap.State.CAUGHT)
	trap._process(SnareTrap.SPOIL_SECONDS + 0.1)
	assert_eq(trap.state, SnareTrap.State.SPOILED)
	assert_eq(trap.smell_strength(), SnareTrap.SPOILED_SMELL, "미회수 포획물은 썩은 냄새가 커진다")
	trap.interact(player)
	assert_eq(player.inventory.count_of(&"raw_meat"), 2)
	assert_eq(player.inventory.count_of(&"hide"), 1)


func test_seeded_snare_failure_leaves_scavenger_and_trap_armed() -> void:
	var trap := add_child_autofree(SnareScene.instantiate()) as SnareTrap
	var scavenger := add_child_autofree(ScavengerScene.instantiate()) as Scavenger
	assert_false(trap.attempt_capture(scavenger, 0.95))
	assert_eq(trap.state, SnareTrap.State.ARMED)
	assert_true(is_instance_valid(scavenger))


func test_shelter_is_one_use_rest_and_save_gate() -> void:
	var root: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var player := PlayerScene.instantiate() as Player
	root.add_child(player)
	var shelter := ShelterScene.instantiate() as FieldShelter
	root.add_child(shelter)
	player.stats.fatigue = 80.0
	shelter.on_hold_started(player)
	assert_eq(player.stats._rest_multiplier, shelter.fatigue_recovery_multiplier)
	shelter.on_hold_ended(player)
	assert_eq(player.stats._rest_multiplier, 1.0)
	shelter.interact(player)
	assert_true(shelter.used)
	assert_false(shelter.can_interact(player), "사용 후 잔해는 다시 회수·사용할 수 없다")


func test_installation_state_survives_real_json_round_trip() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	var service := main.get_node("SaveService") as SaveService
	service.enabled = true
	service.save_path = TEST_SAVE
	var trap := SnareScene.instantiate() as SnareTrap
	trap.name = "SavedSnare"
	main.add_child(trap)
	trap.global_position = Vector2(91.0, 37.0)
	trap.apply_state(SnareTrap.State.SPOILED, 240.0, 2, 1)
	var shelter := ShelterScene.instantiate() as FieldShelter
	shelter.name = "SavedShelter"
	main.add_child(shelter)
	shelter.global_position = Vector2(-40.0, 88.0)
	shelter.apply_state(true)

	assert_true(service.save_now(&"test"))
	var loaded := SaveService.load_file(TEST_SAVE)
	assert_true(loaded.ok)
	assert_true(loaded.snapshot.installations[0].state is int,
		"JSON 숫자 정규화 계층이 설치물 enum을 int로 복원해야 한다")
	trap.free()
	shelter.free()
	assert_true(service.apply_snapshot(loaded.snapshot))
	var restored_trap := main.get_node_or_null("SavedSnare") as SnareTrap
	var restored_shelter := main.get_node_or_null("SavedShelter") as FieldShelter
	assert_not_null(restored_trap)
	assert_not_null(restored_shelter)
	assert_eq(restored_trap.state, SnareTrap.State.SPOILED)
	assert_eq(restored_trap.raw_meat_yield, 2)
	assert_true(restored_shelter.used)

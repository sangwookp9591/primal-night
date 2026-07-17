extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const InventoryScreenScene: PackedScene = preload("res://scenes/ui/inventory/inventory_screen.tscn")

var _opened_screen: InventoryScreen = null


func after_each() -> void:
	if _opened_screen != null and is_instance_valid(_opened_screen):
		_opened_screen.close()
	_opened_screen = null
	Input.action_release("move_right")
	get_tree().paused = false


func _make_player_and_screen() -> Dictionary:
	var root: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	root.add_child(player)
	var screen: InventoryScreen = InventoryScreenScene.instantiate()
	root.add_child(screen)
	await wait_physics_frames(1)
	screen.bind(player)
	return { root = root, player = player, screen = screen }


func _press_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	get_viewport().push_input(press)


func _action_has_key(action: StringName, key: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event == null:
			continue
		if key_event.physical_keycode == key or key_event.keycode == key:
			return true
	return false


func test_tab_focus_collision_is_resolved_by_input_map_choice() -> void:
	assert_false(_action_has_key(&"ui_focus_next", KEY_TAB),
		"W5-T7 chose WEEK5_6_PLAN §6 option 1: Tab is removed from ui_focus_next")
	assert_false(_action_has_key(&"ui_focus_prev", KEY_TAB),
		"W5-T7 chose WEEK5_6_PLAN §6 option 1: Tab is removed from ui_focus_prev")
	assert_true(_action_has_key(&"toggle_inventory", KEY_TAB),
		"Tab is reserved for the inventory/notebook screen")


func test_tab_toggles_inventory_screen_even_with_focused_control() -> void:
	var made: Dictionary = await _make_player_and_screen()
	var screen: InventoryScreen = made.screen
	_opened_screen = screen

	var focus_sink := Button.new()
	focus_sink.focus_mode = Control.FOCUS_ALL
	(made.root as Node).add_child(focus_sink)
	focus_sink.grab_focus()

	_press_key(KEY_TAB)
	assert_true(screen.is_open(), "literal Tab input should open the screen")

	_press_key(KEY_TAB)
	assert_false(screen.is_open(), "literal Tab input should close the screen")


func test_inventory_screen_displays_slots_weight_and_accumulated_notes() -> void:
	var made: Dictionary = await _make_player_and_screen()
	var player: Player = made.player
	var screen: InventoryScreen = made.screen
	player.inventory.add_item(&"stone", 3)
	player.inventory.add_item(&"raw_meat", 1)
	var knowledge := CraftingKnowledge.ensure_on(player)
	knowledge.apply_observation(&"craft_bait", &"hint", "날고기는 냄새가 강하다.", 12.0)
	knowledge.apply_observation(&"craft_bait", &"success", "미끼 제작 성공.", 18.0)

	screen.open()
	_opened_screen = screen

	assert_true(screen.weight_text().contains("무게"))
	assert_true(screen.weight_text().contains("/"))
	assert_true(screen.slot_text(0).contains("돌"))
	assert_true(screen.slot_text(0).contains("3"))
	assert_true(screen.notes_text().contains("craft_bait"))
	assert_true(screen.notes_text().contains("날고기는 냄새가 강하다."))
	assert_true(screen.notes_text().contains("미끼 제작 성공."))


func test_open_screen_pauses_single_player_and_blocks_movement() -> void:
	var made: Dictionary = await _make_player_and_screen()
	var player: Player = made.player
	var screen: InventoryScreen = made.screen

	screen.open()
	_opened_screen = screen
	Input.action_press("move_right")
	await wait_physics_frames(2)

	assert_true(get_tree().paused, "single-player inventory screen pauses the tree")
	assert_true(player.movement_locked, "open inventory locks player movement input")

	screen.close()
	assert_false(get_tree().paused)
	assert_false(player.movement_locked)

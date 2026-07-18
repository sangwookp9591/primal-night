extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const InventoryScreenScene: PackedScene = preload("res://scenes/ui/inventory/inventory_screen.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")

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


func _make_storage_screen() -> Dictionary:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var player := main.get_node("Player") as Player
	var screen := main.get_node("InventoryScreen") as InventoryScreen
	var cache := main.get_node("StorageCache") as StorageCache
	player.global_position = cache.global_position
	return { root = main, player = player, screen = screen, cache = cache }


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


func test_equipment_slots_and_keyboard_equip_unequip_are_available() -> void:
	var made: Dictionary = await _make_player_and_screen()
	var player: Player = made.player
	var screen: InventoryScreen = made.screen
	screen.open()
	_opened_screen = screen

	assert_true(screen.equipment_text(&"outfit").contains("흰 나시"))
	assert_true(screen.equipment_text(&"back").contains("-"))
	assert_true(screen.equipment_text(&"main_hand").contains("-"))

	_press_key(KEY_ESCAPE)
	assert_eq(player.equipment.get_equipped(&"outfit"), &"")
	assert_eq(player.inventory.count_of(&"white_underwear"), 1)

	_press_key(KEY_ENTER)
	assert_eq(player.equipment.get_equipped(&"outfit"), &"white_underwear")
	assert_eq(player.inventory.count_of(&"white_underwear"), 0)


func test_storage_mode_space_takes_first_item_from_storage() -> void:
	var made: Dictionary = await _make_storage_screen()
	var player: Player = made.player
	var screen: InventoryScreen = made.screen
	var cache: StorageCache = made.cache
	assert_eq(cache.inventory.add_item(&"wood", 1), 1)
	screen.open_storage(player, cache)
	_opened_screen = screen

	_press_key(KEY_SPACE)

	assert_eq(player.inventory.count_of(&"wood"), 1)
	assert_eq(cache.inventory.count_of(&"wood"), 0)


func test_storage_mode_enter_puts_selected_inventory_item_into_storage() -> void:
	var made: Dictionary = await _make_storage_screen()
	var player: Player = made.player
	var screen: InventoryScreen = made.screen
	var cache: StorageCache = made.cache
	assert_eq(player.inventory.add_item(&"wood", 1), 1)
	screen.open_storage(player, cache)
	_opened_screen = screen

	_press_key(KEY_ENTER)

	assert_eq(player.inventory.count_of(&"wood"), 0)
	assert_eq(cache.inventory.count_of(&"wood"), 1)


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

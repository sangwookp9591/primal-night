extends GutTest

const TEST_CONFIG := "/tmp/primal_night_input_bindings_test.cfg"

var _originals: Dictionary = {}

func before_each() -> void:
	_originals.clear()
	for action in InputBindingService.ACTIONS:
		_originals[action] = _duplicate_events(InputMap.action_get_events(action))
	if FileAccess.file_exists(TEST_CONFIG):
		DirAccess.remove_absolute(TEST_CONFIG)

func after_each() -> void:
	for action in InputBindingService.ACTIONS:
		InputMap.action_erase_events(action)
		for event in _originals[action]:
			InputMap.action_add_event(action, event)
	if FileAccess.file_exists(TEST_CONFIG):
		DirAccess.remove_absolute(TEST_CONFIG)

func test_rebind_replaces_current_binding() -> void:
	var service := _make_service()
	var conflict := service.rebind(&"move_up", _key(KEY_Z))
	assert_eq(conflict, &"")
	var events := InputMap.action_get_events(&"move_up")
	assert_eq(events.size(), 1)
	assert_eq((events[0] as InputEventKey).physical_keycode, KEY_Z)

func test_binding_persistence_round_trip() -> void:
	var service := _make_service()
	service.rebind(&"quick_craft", _button(JOY_BUTTON_RIGHT_SHOULDER))
	InputMap.action_erase_events(&"quick_craft")
	assert_eq(service.load_bindings(), OK)
	var loaded := InputMap.action_get_events(&"quick_craft")
	assert_eq(loaded.size(), 1)
	assert_eq((loaded[0] as InputEventJoypadButton).button_index, JOY_BUTTON_RIGHT_SHOULDER)

func test_restore_defaults_restores_captured_events() -> void:
	var service := _make_service()
	var expected := InputBindingService.event_text(InputMap.action_get_events(&"interact")[0])
	service.rebind(&"interact", _key(KEY_Z))
	service.restore_defaults()
	assert_eq(InputBindingService.event_text(InputMap.action_get_events(&"interact")[0]), expected)

func test_conflict_moves_binding_to_new_action() -> void:
	var service := _make_service()
	service.rebind(&"move_up", _key(KEY_Z))
	var conflict := service.rebind(&"move_down", _key(KEY_Z))
	assert_eq(conflict, &"move_up")
	assert_true(InputMap.action_get_events(&"move_up").is_empty())
	assert_eq((InputMap.action_get_events(&"move_down")[0] as InputEventKey).physical_keycode, KEY_Z)

func test_missing_config_is_noop_for_headless_harnesses() -> void:
	var before := InputBindingService.event_text(InputMap.action_get_events(&"attack")[0])
	var service := _make_service()
	service.config_path = "/tmp/primal_night_missing_input_bindings.cfg"
	if FileAccess.file_exists(service.config_path):
		DirAccess.remove_absolute(service.config_path)
	assert_eq(service.load_bindings(), OK)
	assert_eq(InputBindingService.event_text(InputMap.action_get_events(&"attack")[0]), before)

func _make_service() -> InputBindingService:
	var service := autofree(InputBindingService.new()) as InputBindingService
	service.config_path = TEST_CONFIG
	service.capture_defaults()
	return service

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	return event

func _duplicate_events(events: Array[InputEvent]) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in events:
		result.append(event.duplicate())
	return result

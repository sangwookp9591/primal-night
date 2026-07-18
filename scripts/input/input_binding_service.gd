class_name InputBindingService
extends Node

const DEFAULT_CONFIG_PATH := "user://input_bindings.cfg"
const ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"attack",
	&"run",
	&"crouch",
	&"interact",
	&"cycle_target",
	&"toggle_inventory",
	&"quick_craft",
	&"place_lure",
]

var config_path := DEFAULT_CONFIG_PATH
var _defaults: Dictionary = {}

func _ready() -> void:
	capture_defaults()
	load_bindings()

func capture_defaults() -> void:
	_defaults.clear()
	for action in ACTIONS:
		if InputMap.has_action(action):
			_defaults[action] = _duplicate_events(InputMap.action_get_events(action))

func rebind(action: StringName, event: InputEvent) -> StringName:
	if not ACTIONS.has(action) or not InputMap.has_action(action):
		return &""
	var normalized := normalize_event(event)
	if normalized == null:
		return &""
	var conflict := find_conflict(action, normalized)
	if not conflict.is_empty():
		InputMap.action_erase_events(conflict)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, normalized)
	save_bindings()
	return conflict

func find_conflict(action: StringName, event: InputEvent) -> StringName:
	for other in ACTIONS:
		if other == action or not InputMap.has_action(other):
			continue
		for bound in InputMap.action_get_events(other):
			if events_match(bound, event):
				return other
	return &""

func restore_defaults() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action) or not _defaults.has(action):
			continue
		InputMap.action_erase_events(action)
		for event in _defaults[action]:
			InputMap.action_add_event(action, event.duplicate())
	save_bindings()

func save_bindings() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	for action in ACTIONS:
		if not InputMap.has_action(action):
			continue
		var encoded: Array[Dictionary] = []
		for event in InputMap.action_get_events(action):
			var data := encode_event(event)
			if not data.is_empty():
				encoded.append(data)
		config.set_value("bindings", String(action), encoded)
	return config.save(config_path)

func load_bindings() -> Error:
	var config := ConfigFile.new()
	var error := config.load(config_path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		return error
	for action in ACTIONS:
		if not InputMap.has_action(action) or not config.has_section_key("bindings", String(action)):
			continue
		var encoded: Variant = config.get_value("bindings", String(action), [])
		if not encoded is Array:
			continue
		var decoded: Array[InputEvent] = []
		for data in encoded:
			if data is Dictionary:
				var event := decode_event(data)
				if event != null:
					decoded.append(event)
		InputMap.action_erase_events(action)
		for event in decoded:
			InputMap.action_add_event(action, event)
	return OK

func binding_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "미지정"
	var labels: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		labels.append(event_text(event))
	return " / ".join(labels) if not labels.is_empty() else "미지정"

static func normalize_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var source := event as InputEventKey
		var key := InputEventKey.new()
		key.physical_keycode = source.physical_keycode
		key.keycode = source.keycode if source.physical_keycode == 0 else 0
		return key
	if event is InputEventJoypadButton:
		var source := event as InputEventJoypadButton
		var button := InputEventJoypadButton.new()
		button.button_index = source.button_index
		button.device = -1
		return button
	return null

static func events_match(left: InputEvent, right: InputEvent) -> bool:
	if left is InputEventKey and right is InputEventKey:
		var a := left as InputEventKey
		var b := right as InputEventKey
		if a.physical_keycode != 0 or b.physical_keycode != 0:
			return a.physical_keycode == b.physical_keycode
		return a.keycode == b.keycode
	if left is InputEventJoypadButton and right is InputEventJoypadButton:
		return (left as InputEventJoypadButton).button_index == (right as InputEventJoypadButton).button_index
	return false

static func encode_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": key.physical_keycode,
			"keycode": key.keycode,
		}
	if event is InputEventJoypadButton:
		return {
			"type": "joypad_button",
			"button_index": (event as InputEventJoypadButton).button_index,
		}
	return {}

static func decode_event(data: Dictionary) -> InputEvent:
	match String(data.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(data.get("physical_keycode", 0))
			key.keycode = int(data.get("keycode", 0))
			return key
		"joypad_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(data.get("button_index", -1))
			button.device = -1
			return button if button.button_index >= 0 else null
	return null

static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		return (event as InputEventKey).as_text()
	if event is InputEventJoypadButton:
		return "패드 버튼 %d" % (event as InputEventJoypadButton).button_index
	return event.as_text()

static func _duplicate_events(events: Array[InputEvent]) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in events:
		result.append(event.duplicate())
	return result

class_name InventoryScreen
extends CanvasLayer

## 회색 상자 인벤토리/노트 열람 화면. Tab 토글은 project.godot 에서
## ui_focus_next 의 Tab 기본 바인딩을 제거한 뒤 이 액션만 받는다.

const SLOT_SIZE: Vector2 = Vector2(120.0, 42.0)

@onready var _panel: PanelContainer = $Root/Panel
@onready var _weight_label: Label = $Root/Panel/Layout/Header/Weight
@onready var _slot_grid: GridContainer = $Root/Panel/Layout/Columns/Inventory/Slots
@onready var _notes: VBoxContainer = $Root/Panel/Layout/Columns/Notebook/Notes

var _player: Player = null
var _game_data: Node = null
var _slot_labels: Array[Label] = []
var _was_paused_by_screen: bool = false
var _previous_movement_locked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game_data = get_node("/root/GameData")
	visible = false
	var found: Node = get_tree().get_first_node_in_group(&"player")
	if found != null:
		bind(found as Player)


func bind(player: Player) -> void:
	if player == null or _player == player:
		return
	_player = player
	_rebuild_slot_labels()
	_player.inventory.changed.connect(_refresh)
	CraftingKnowledge.ensure_on(_player).observation_added.connect(func(_text: String) -> void:
		_refresh())
	_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible:
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if _player == null:
		var found: Node = get_tree().get_first_node_in_group(&"player")
		if found != null:
			bind(found as Player)
	if _player == null:
		return
	visible = true
	_panel.grab_focus()
	_previous_movement_locked = _player.movement_locked
	_player.movement_locked = true
	if multiplayer.get_peers().is_empty() and not get_tree().paused:
		get_tree().paused = true
		_was_paused_by_screen = true
	_refresh()


func close() -> void:
	visible = false
	if _player != null:
		_player.movement_locked = _previous_movement_locked
	if _was_paused_by_screen:
		get_tree().paused = false
		_was_paused_by_screen = false


func is_open() -> bool:
	return visible


func weight_text() -> String:
	return _weight_label.text


func slot_text(index: int) -> String:
	if index < 0 or index >= _slot_labels.size():
		return ""
	return _slot_labels[index].text


func notes_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for child: Node in _notes.get_children():
		var label := child as Label
		if label != null:
			lines.append(label.text)
	return "\n".join(lines)


func _rebuild_slot_labels() -> void:
	for child: Node in _slot_grid.get_children():
		child.queue_free()
	_slot_labels.clear()
	_slot_grid.columns = mini(_player.inventory.slot_count, 4)
	for index: int in range(_player.inventory.slot_count):
		var label := Label.new()
		label.custom_minimum_size = SLOT_SIZE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_slot_grid.add_child(label)
		_slot_labels.append(label)


func _refresh() -> void:
	if _player == null:
		return
	_weight_label.text = "무게 %.1f / %.1f" % [
		_player.inventory.total_weight(), _player.inventory.max_weight]
	for index: int in range(_slot_labels.size()):
		var slot: Dictionary = _player.inventory.get_slot(index)
		if slot.is_empty():
			_slot_labels[index].text = "%02d -" % (index + 1)
			continue
		var item: ItemData = _game_data.get_item(slot["id"])
		var display_name: String = item.display_name if item != null else String(slot["id"])
		_slot_labels[index].text = "%02d %s x%d" % [index + 1, display_name, int(slot["count"])]
	_refresh_notes()


func _refresh_notes() -> void:
	for child: Node in _notes.get_children():
		child.queue_free()
	var knowledge := CraftingKnowledge.ensure_on(_player)
	var discovered: Array[StringName] = knowledge.discovered_recipe_ids()
	var discovered_label := Label.new()
	discovered_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discovered_label.text = "발견한 제작법: %s" % _format_recipe_ids(discovered)
	_notes.add_child(discovered_label)
	for observation: Dictionary in knowledge.observations():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "[%s] %s" % [String(observation.recipe_id), String(observation.text)]
		_notes.add_child(label)


func _format_recipe_ids(ids: Array[StringName]) -> String:
	if ids.is_empty():
		return "-"
	var values: PackedStringArray = PackedStringArray()
	for id: StringName in ids:
		values.append(String(id))
	return ", ".join(values)

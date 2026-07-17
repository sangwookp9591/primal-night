class_name InventoryScreen
extends CanvasLayer

## 회색 상자 인벤토리/노트 열람 화면. Tab 토글은 project.godot 에서
## ui_focus_next 의 Tab 기본 바인딩을 제거한 뒤 이 액션만 받는다.

const SLOT_SIZE: Vector2 = Vector2(120.0, 42.0)

@onready var _panel: PanelContainer = $Root/Panel
@onready var _weight_label: Label = $Root/Panel/Layout/Header/Weight
@onready var _slot_grid: GridContainer = $Root/Panel/Layout/Columns/Inventory/Slots
@onready var _equipment_slots: HBoxContainer = $Root/Panel/Layout/Columns/Inventory/EquipmentSlots
@onready var _notes: VBoxContainer = $Root/Panel/Layout/Columns/Notebook/Notes

var _player: Player = null
var _game_data: Node = null
var _slot_labels: Array[Label] = []
var _slot_icons: Array[TextureRect] = []
var _equipment_labels: Dictionary = {}
var _selected_inventory_index: int = 0
var _selected_equipment_index: int = 0
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
	_rebuild_equipment_labels()
	_rebuild_slot_labels()
	_player.inventory.changed.connect(_refresh)
	_player.equipment.equipment_changed.connect(func(_slot: StringName, _item_id: StringName) -> void:
		_refresh())
	CraftingKnowledge.ensure_on(_player).observation_added.connect(func(_text: String) -> void:
		_refresh())
	_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible:
		if event.is_action_pressed(&"ui_up"):
			_selected_inventory_index = maxi(_selected_inventory_index - 1, 0)
			_refresh()
		elif event.is_action_pressed(&"ui_down"):
			_selected_inventory_index = mini(
				_selected_inventory_index + 1, _player.inventory.slot_count - 1)
			_refresh()
		elif event.is_action_pressed(&"ui_left"):
			_selected_equipment_index = maxi(_selected_equipment_index - 1, 0)
			_refresh()
		elif event.is_action_pressed(&"ui_right"):
			_selected_equipment_index = mini(
				_selected_equipment_index + 1, EquipmentComponent.SLOTS.size() - 1)
			_refresh()
		elif event.is_action_pressed(&"ui_accept"):
			_toggle_selected_equipment()
		elif event.is_action_pressed(&"ui_cancel"):
			_unequip_selected_slot()
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


func slot_icon(index: int) -> Texture2D:
	if index < 0 or index >= _slot_icons.size():
		return null
	return _slot_icons[index].texture


func equipment_text(slot: StringName) -> String:
	var label: Label = _equipment_labels.get(slot)
	return label.text if label != null else ""


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
	_slot_icons.clear()
	_slot_grid.columns = mini(_player.inventory.slot_count, 4)
	for index: int in range(_player.inventory.slot_count):
		var slot_view := HBoxContainer.new()
		slot_view.custom_minimum_size = SLOT_SIZE
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28.0, 36.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_view.add_child(icon)
		slot_view.add_child(label)
		_slot_grid.add_child(slot_view)
		_slot_icons.append(icon)
		_slot_labels.append(label)


func _rebuild_equipment_labels() -> void:
	for child: Node in _equipment_slots.get_children():
		child.queue_free()
	_equipment_labels.clear()
	for slot: StringName in EquipmentComponent.SLOTS:
		var view := VBoxContainer.new()
		view.custom_minimum_size = Vector2(160.0, 64.0)
		var silhouette := ColorRect.new()
		silhouette.custom_minimum_size = Vector2(34.0, 28.0)
		silhouette.color = Color(0.18, 0.2, 0.19, 1.0)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		view.add_child(silhouette)
		view.add_child(label)
		_equipment_slots.add_child(view)
		_equipment_labels[slot] = label


func _refresh() -> void:
	if _player == null:
		return
	_weight_label.text = "무게 %.1f / %.1f" % [
		_player.inventory.total_weight(), _player.inventory.max_weight]
	for index: int in range(_slot_labels.size()):
		var slot: Dictionary = _player.inventory.get_slot(index)
		if slot.is_empty():
			_slot_labels[index].text = "%s%02d -" % [
				"> " if index == _selected_inventory_index else "", index + 1]
			_slot_icons[index].texture = null
			continue
		_slot_icons[index].texture = WorldItem.icon_texture(slot["id"])
		var item: ItemData = _game_data.get_item(slot["id"])
		var display_name: String = item.display_name if item != null else String(slot["id"])
		var equipped_marker: String = " [장착]" if _is_equipped(slot["id"]) else ""
		_slot_labels[index].text = "%s%02d %s x%d%s" % [
			"> " if index == _selected_inventory_index else "",
			index + 1, display_name, int(slot["count"]), equipped_marker]
	for slot_index: int in range(EquipmentComponent.SLOTS.size()):
		var equip_slot: StringName = EquipmentComponent.SLOTS[slot_index]
		var item_id: StringName = _player.equipment.get_equipped(equip_slot)
		var display_name: String = "-"
		if item_id != &"":
			var item: ItemData = _game_data.get_item(item_id)
			display_name = item.display_name if item != null else "알 수 없음"
		var label: Label = _equipment_labels.get(equip_slot)
		if label != null:
			label.text = "%s%s\n%s" % [
				"> " if slot_index == _selected_equipment_index else "",
				_slot_display_name(equip_slot), display_name]
	_refresh_notes()


func _toggle_selected_equipment() -> void:
	var selected: Dictionary = _player.inventory.get_slot(_selected_inventory_index)
	if selected.is_empty():
		return
	var item_id := StringName(selected["id"])
	var item: ItemData = _game_data.get_item(item_id)
	if not item is WearableData:
		return
	var wearable := item as WearableData
	if _player.equipment.get_equipped(wearable.equip_slot) == item_id:
		_player.equipment.request_unequip(wearable.equip_slot)
	else:
		_player.equipment.request_equip(item_id)


func _is_equipped(item_id: StringName) -> bool:
	for equip_slot: StringName in EquipmentComponent.SLOTS:
		if _player.equipment.get_equipped(equip_slot) == item_id:
			return true
	return false


func _unequip_selected_slot() -> void:
	var equip_slot: StringName = EquipmentComponent.SLOTS[_selected_equipment_index]
	_player.equipment.request_unequip(equip_slot)


func _slot_display_name(slot: StringName) -> String:
	match slot:
		&"outfit":
			return "의상"
		&"back":
			return "등"
		&"main_hand":
			return "주 손"
	return String(slot)


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

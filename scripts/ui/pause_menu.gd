class_name PauseMenu
extends CanvasLayer

const TITLE_SCENE := "res://scenes/ui/title/title_screen.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"

@export var save_service_path: NodePath = ^"../SaveService"
@export var player_path: NodePath = ^"../Player"
@export var objective_path: NodePath = ^"../LoopObjective"

var _panel: PanelContainer
var _heading: Label
var _message: Label
var _continue: Button
var _save: Button
var _reload: Button
var _title: Button
var _death_shown: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.damage_taken.connect(_on_damage_taken)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _death_shown:
		if visible:
			resume()
		else:
			open_pause()
		get_viewport().set_input_as_handled()

func open_pause() -> void:
	_death_shown = false
	_heading.text = "일시정지" if multiplayer.get_peers().is_empty() else "메뉴"
	_message.text = "" if multiplayer.get_peers().is_empty() \
		else "협동 세션의 시간과 세계는 계속 흐릅니다."
	_continue.visible = true
	_save.visible = multiplayer.is_server()
	_reload.visible = false
	visible = true
	if multiplayer.get_peers().is_empty():
		get_tree().paused = true
	_continue.grab_focus.call_deferred()

func resume() -> void:
	get_tree().paused = false
	visible = false

func show_death(cause: String) -> void:
	_death_shown = true
	var save_service := get_node_or_null(save_service_path) as SaveService
	if save_service != null:
		save_service.record_death(cause)
	get_tree().paused = multiplayer.get_peers().is_empty()
	_heading.text = "사망"
	_message.text = cause
	_continue.visible = false
	_save.visible = false
	_reload.visible = SaveService.has_save()
	_title.visible = true
	visible = true
	(_reload if _reload.visible else _title).grab_focus.call_deferred()

func _save_pressed() -> void:
	var service := get_node(save_service_path) as SaveService
	_message.text = "저장했습니다." if service.save_now(&"manual") else service.last_error

func _reload_pressed() -> void:
	var prepared := SaveService.prepare_continue(SaveService.DEFAULT_SAVE_PATH, true)
	if not prepared.ok:
		_message.text = prepared.message
		return
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_SCENE)

func _title_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)

func _on_damage_taken(target: Node, _amount: float, _kind: StringName) -> void:
	var player := get_node(player_path) as Player
	if target == player and not player.health.is_alive():
		var objective := get_node(objective_path) as LoopObjective
		show_death.call_deferred(objective.compose_death_cause())

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(430, 0)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	_panel.add_child(column)
	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override(&"font_size", 28)
	column.add_child(_heading)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	_continue = _button("계속", resume)
	_save = _button("저장", _save_pressed)
	_reload = _button("마지막 저장에서 다시", _reload_pressed)
	_title = _button("타이틀로", _title_pressed)
	for button: Button in [_continue, _save, _reload, _title]:
		column.add_child(button)

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button

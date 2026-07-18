class_name TitleScreen
extends Control

const MAIN_SCENE := "res://scenes/main.tscn"

@onready var _main_menu: VBoxContainer = $Center/MenuPanel/Content/MainMenu
@onready var _difficulty_menu: VBoxContainer = $Center/MenuPanel/Content/DifficultyMenu
@onready var _join_menu: VBoxContainer = $Center/MenuPanel/Content/JoinMenu
@onready var _controls_menu: VBoxContainer = $Center/MenuPanel/Content/ControlsMenu
@onready var _binding_rows: VBoxContainer = $Center/MenuPanel/Content/ControlsMenu/Bindings/Rows
@onready var _address: LineEdit = $Center/MenuPanel/Content/JoinMenu/Address
@onready var _status: Label = $Center/MenuPanel/Content/Status
@onready var _overwrite_menu: VBoxContainer = $Center/MenuPanel/Content/OverwriteMenu
@onready var _session: LocalSessionService = $NetSession

var _launch_mode: StringName = &"single"
var _waiting_action: StringName = &""
var _binding_buttons: Dictionary = {}

const ACTION_LABELS := {
	&"move_up": "위로 이동",
	&"move_down": "아래로 이동",
	&"move_left": "왼쪽 이동",
	&"move_right": "오른쪽 이동",
	&"attack": "공격",
	&"run": "달리기",
	&"crouch": "웅크리기",
	&"interact": "상호작용 / 줍기",
	&"cycle_target": "대상 전환",
	&"toggle_inventory": "인벤토리",
	&"quick_craft": "빠른 제작",
	&"place_lure": "미끼 놓기",
}

func _ready() -> void:
	$Center/MenuPanel/Content/MainMenu/Single.pressed.connect(_choose_mode.bind(&"single"))
	$Center/MenuPanel/Content/MainMenu/Continue.pressed.connect(_continue_game)
	$Center/MenuPanel/Content/MainMenu/Host.pressed.connect(_choose_mode.bind(&"host"))
	$Center/MenuPanel/Content/MainMenu/Join.pressed.connect(show_join)
	$Center/MenuPanel/Content/MainMenu/Controls.pressed.connect(show_controls)
	$Center/MenuPanel/Content/MainMenu/Quit.pressed.connect(get_tree().quit)
	$Center/MenuPanel/Content/DifficultyMenu/Gentle.pressed.connect(_launch_with_difficulty.bind(&"gentle"))
	$Center/MenuPanel/Content/DifficultyMenu/Standard.pressed.connect(_launch_with_difficulty.bind(&"standard"))
	$Center/MenuPanel/Content/DifficultyMenu/Harsh.pressed.connect(_launch_with_difficulty.bind(&"harsh"))
	$Center/MenuPanel/Content/DifficultyMenu/Back.pressed.connect(show_main)
	$Center/MenuPanel/Content/JoinMenu/Connect.pressed.connect(_join)
	$Center/MenuPanel/Content/JoinMenu/Back.pressed.connect(show_main)
	$Center/MenuPanel/Content/ControlsMenu/Restore.pressed.connect(_restore_bindings)
	$Center/MenuPanel/Content/ControlsMenu/Back.pressed.connect(show_main)
	$Center/MenuPanel/Content/OverwriteMenu/Confirm.pressed.connect(_confirm_overwrite)
	$Center/MenuPanel/Content/OverwriteMenu/Back.pressed.connect(show_main)
	_build_binding_rows()
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	show_main()

func show_main() -> void:
	_show_only(_main_menu)
	_status.text = ""
	$Center/MenuPanel/Content/MainMenu/Continue.disabled = not SaveService.has_save()
	$Center/MenuPanel/Content/MainMenu/Single.grab_focus.call_deferred()

func show_join() -> void:
	_show_only(_join_menu)
	_status.text = "호스트 주소를 입력하세요. 예: 127.0.0.1:8910"
	_address.grab_focus.call_deferred()

func show_controls() -> void:
	_waiting_action = &""
	_show_only(_controls_menu)
	_status.text = "바꿀 조작을 선택한 뒤 키 또는 패드 버튼을 누르세요."
	_refresh_binding_text()
	if not _binding_buttons.is_empty():
		(_binding_buttons.values()[0] as Button).grab_focus.call_deferred()

func _choose_mode(mode: StringName) -> void:
	_launch_mode = mode
	_show_only(_difficulty_menu)
	_status.text = "난이도는 적 체력이 아니라 생존 규칙을 조절합니다."
	$Center/MenuPanel/Content/DifficultyMenu/Standard.grab_focus.call_deferred()

func _show_only(menu: Control) -> void:
	_main_menu.visible = menu == _main_menu
	_difficulty_menu.visible = menu == _difficulty_menu
	_join_menu.visible = menu == _join_menu
	_controls_menu.visible = menu == _controls_menu
	_overwrite_menu.visible = menu == _overwrite_menu

func _build_binding_rows() -> void:
	var previous: Control = null
	for action in InputBindingService.ACTIONS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = ACTION_LABELS.get(action, String(action))
		label.custom_minimum_size.x = 180
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := Button.new()
		button.custom_minimum_size.x = 210
		button.pressed.connect(_begin_rebind.bind(action))
		row.add_child(label)
		row.add_child(button)
		_binding_rows.add_child(row)
		_binding_buttons[action] = button
		if previous != null:
			previous.focus_neighbor_bottom = previous.get_path_to(button)
			button.focus_neighbor_top = button.get_path_to(previous)
		previous = button
	var restore := $Center/MenuPanel/Content/ControlsMenu/Restore as Button
	var back := $Center/MenuPanel/Content/ControlsMenu/Back as Button
	if previous != null:
		previous.focus_neighbor_bottom = previous.get_path_to(restore)
		restore.focus_neighbor_top = restore.get_path_to(previous)
	restore.focus_neighbor_bottom = restore.get_path_to(back)
	back.focus_neighbor_top = back.get_path_to(restore)
	_refresh_binding_text()

func _begin_rebind(action: StringName) -> void:
	_waiting_action = action
	_status.text = "%s: 다음 키 또는 패드 버튼을 누르세요. (뒤로: 취소)" % ACTION_LABELS.get(action, action)
	(_binding_buttons[action] as Button).text = "입력 대기 중…"

func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action.is_empty():
		return
	if event.is_action_pressed("ui_cancel"):
		_waiting_action = &""
		_status.text = "재바인딩을 취소했습니다."
		_refresh_binding_text()
		get_viewport().set_input_as_handled()
		return
	var accepted: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed)
	if not accepted:
		return
	var action := _waiting_action
	_waiting_action = &""
	var conflict: StringName = InputBindings.rebind(action, event)
	_refresh_binding_text()
	if conflict.is_empty():
		_status.text = "%s 조작을 저장했습니다." % ACTION_LABELS.get(action, action)
	else:
		_status.text = "충돌: %s의 입력을 제거하고 %s에 지정했습니다." % [
			ACTION_LABELS.get(conflict, conflict), ACTION_LABELS.get(action, action)]
	(_binding_buttons[action] as Button).grab_focus()
	get_viewport().set_input_as_handled()

func _restore_bindings() -> void:
	InputBindings.restore_defaults()
	_waiting_action = &""
	_refresh_binding_text()
	_status.text = "모든 조작을 기본값으로 복원하고 저장했습니다."

func _refresh_binding_text() -> void:
	for action in _binding_buttons:
		(_binding_buttons[action] as Button).text = InputBindings.binding_text(action)

func _launch_with_difficulty(id: StringName) -> void:
	if _launch_mode == &"single" and SaveService.has_save():
		DifficultyRuntime.pending_preset_id = id
		_show_only(_overwrite_menu)
		_status.text = "새 게임을 시작하면 기존 저장을 덮어씁니다."
		$Center/MenuPanel/Content/OverwriteMenu/Back.grab_focus.call_deferred()
		return
	_start_new_game(id)

func _start_new_game(id: StringName) -> void:
	DifficultyRuntime.select_for_next_game(id)
	SaveService.launch_requested = true
	if _launch_mode == &"host":
		var error := _session.host_session()
		if error != OK:
			_status.text = failure_message(_session.get_last_connection_failure())
			show_main()
			return
	get_tree().change_scene_to_file(MAIN_SCENE)

func _confirm_overwrite() -> void:
	var error := DirAccess.remove_absolute(SaveService.DEFAULT_SAVE_PATH)
	if error != OK and error != ERR_DOES_NOT_EXIST:
		_status.text = "기존 저장을 지울 수 없어 새 게임을 시작하지 못했습니다."
		return
	_start_new_game(DifficultyRuntime.pending_preset_id)

func _continue_game() -> void:
	var prepared := SaveService.prepare_continue()
	if not prepared.ok:
		_status.text = prepared.message
		$Center/MenuPanel/Content/MainMenu/Continue.disabled = true
		return
	get_tree().change_scene_to_file(MAIN_SCENE)

func _join() -> void:
	_status.text = "접속 중…"
	var error := _session.join_session(_address.text.strip_edges())
	if error != OK:
		_show_join_failure()

func _on_connected_to_server() -> void:
	# 참가자는 표준으로 먼저 열리고, main의 DifficultyRuntime이 호스트 프리셋 RPC를 받는다.
	DifficultyRuntime.select_for_next_game(&"standard")
	SaveService.launch_requested = true
	get_tree().change_scene_to_file(MAIN_SCENE)

func _on_connection_failed() -> void:
	_session.record_async_connection_failure()
	_show_join_failure()

func _show_join_failure() -> void:
	_status.text = failure_message(_session.get_last_connection_failure())
	_show_only(_join_menu)
	$Center/MenuPanel/Content/JoinMenu/Back.grab_focus.call_deferred()

static func failure_message(failure: Dictionary) -> String:
	match StringName(failure.get("reason", &"unknown")):
		&"invalid_invite":
			return "주소 형식이 올바르지 않습니다. IP:port 형식으로 입력하세요."
		&"version_mismatch":
			return "게임 버전이 달라 참가할 수 없습니다. 호스트와 같은 버전을 사용하세요."
		&"connection_failed":
			return "호스트에 연결하지 못했습니다. 주소, 포트, 방화벽을 확인하세요."
		&"host_create_failed":
			return "호스트를 열지 못했습니다. 포트가 사용 중인지 확인하세요."
		_:
			return "세션을 시작하지 못했습니다. 잠시 후 다시 시도하세요."

class_name TitleScreen
extends Control

const MAIN_SCENE := "res://scenes/main.tscn"

@onready var _main_menu: VBoxContainer = $Center/MenuPanel/Content/MainMenu
@onready var _difficulty_menu: VBoxContainer = $Center/MenuPanel/Content/DifficultyMenu
@onready var _join_menu: VBoxContainer = $Center/MenuPanel/Content/JoinMenu
@onready var _address: LineEdit = $Center/MenuPanel/Content/JoinMenu/Address
@onready var _status: Label = $Center/MenuPanel/Content/Status
@onready var _session: LocalSessionService = $NetSession

var _launch_mode: StringName = &"single"

func _ready() -> void:
	$Center/MenuPanel/Content/MainMenu/Single.pressed.connect(_choose_mode.bind(&"single"))
	$Center/MenuPanel/Content/MainMenu/Host.pressed.connect(_choose_mode.bind(&"host"))
	$Center/MenuPanel/Content/MainMenu/Join.pressed.connect(show_join)
	$Center/MenuPanel/Content/MainMenu/Quit.pressed.connect(get_tree().quit)
	$Center/MenuPanel/Content/DifficultyMenu/Gentle.pressed.connect(_launch_with_difficulty.bind(&"gentle"))
	$Center/MenuPanel/Content/DifficultyMenu/Standard.pressed.connect(_launch_with_difficulty.bind(&"standard"))
	$Center/MenuPanel/Content/DifficultyMenu/Harsh.pressed.connect(_launch_with_difficulty.bind(&"harsh"))
	$Center/MenuPanel/Content/DifficultyMenu/Back.pressed.connect(show_main)
	$Center/MenuPanel/Content/JoinMenu/Connect.pressed.connect(_join)
	$Center/MenuPanel/Content/JoinMenu/Back.pressed.connect(show_main)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	show_main()

func show_main() -> void:
	_show_only(_main_menu)
	_status.text = ""
	$Center/MenuPanel/Content/MainMenu/Single.grab_focus.call_deferred()

func show_join() -> void:
	_show_only(_join_menu)
	_status.text = "호스트 주소를 입력하세요. 예: 127.0.0.1:8910"
	_address.grab_focus.call_deferred()

func _choose_mode(mode: StringName) -> void:
	_launch_mode = mode
	_show_only(_difficulty_menu)
	_status.text = "난이도는 적 체력이 아니라 생존 규칙을 조절합니다."
	$Center/MenuPanel/Content/DifficultyMenu/Standard.grab_focus.call_deferred()

func _show_only(menu: Control) -> void:
	_main_menu.visible = menu == _main_menu
	_difficulty_menu.visible = menu == _difficulty_menu
	_join_menu.visible = menu == _join_menu

func _launch_with_difficulty(id: StringName) -> void:
	DifficultyRuntime.select_for_next_game(id)
	if _launch_mode == &"host":
		var error := _session.host_session()
		if error != OK:
			_status.text = failure_message(_session.get_last_connection_failure())
			show_main()
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

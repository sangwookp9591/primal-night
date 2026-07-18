extends GutTest

const TitleScene: PackedScene = preload("res://scenes/ui/title/title_screen.tscn")

func test_title_exposes_single_host_join_quit_and_focus_chain() -> void:
	var title: TitleScreen = add_child_autofree(TitleScene.instantiate()) as TitleScreen
	await wait_process_frames(2)
	var single := title.get_node("Center/MenuPanel/Content/MainMenu/Single") as Button
	var host := title.get_node("Center/MenuPanel/Content/MainMenu/Host") as Button
	var join := title.get_node("Center/MenuPanel/Content/MainMenu/Join") as Button
	var quit := title.get_node("Center/MenuPanel/Content/MainMenu/Quit") as Button
	assert_false(single.focus_neighbor_bottom.is_empty())
	assert_false(host.focus_neighbor_bottom.is_empty())
	assert_false(join.focus_neighbor_bottom.is_empty())
	assert_false(quit.focus_neighbor_top.is_empty())
	assert_true(single.has_focus())

func test_single_selection_opens_difficulty_menu() -> void:
	var title: TitleScreen = add_child_autofree(TitleScene.instantiate()) as TitleScreen
	await wait_process_frames(2)
	title.get_node("Center/MenuPanel/Content/MainMenu/Single").pressed.emit()
	assert_true(title.get_node("Center/MenuPanel/Content/DifficultyMenu").visible)
	assert_false(title.get_node("Center/MenuPanel/Content/MainMenu").visible)

func test_join_invalid_address_shows_human_readable_failure_and_stays_in_title() -> void:
	var title: TitleScreen = add_child_autofree(TitleScene.instantiate()) as TitleScreen
	await wait_process_frames(2)
	title.show_join()
	title.get_node("Center/MenuPanel/Content/JoinMenu/Address").text = "잘못된주소"
	title.get_node("Center/MenuPanel/Content/JoinMenu/Connect").pressed.emit()
	var status := title.get_node("Center/MenuPanel/Content/Status") as Label
	assert_string_contains(status.text, "IP:port")
	assert_true(title.get_node("Center/MenuPanel/Content/JoinMenu").visible)

func test_failure_messages_cover_version_and_network_failures() -> void:
	assert_string_contains(TitleScreen.failure_message({reason = &"version_mismatch"}), "버전")
	assert_string_contains(TitleScreen.failure_message({reason = &"connection_failed"}), "연결")

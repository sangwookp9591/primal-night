extends GutTest

const ThemeResource: Theme = preload("res://scenes/ui/theme/primal_night_theme.tres")
const HudScene: PackedScene = preload("res://scenes/ui/hud/hud.tscn")
const InventoryScreenScene: PackedScene = preload("res://scenes/ui/inventory/inventory_screen.tscn")
const TitleScene: PackedScene = preload("res://scenes/ui/title/title_screen.tscn")
const BootScene: PackedScene = preload("res://scenes/boot.tscn")
const PerformanceOverlayScene: PackedScene = preload("res://scenes/debug/performance_overlay.tscn")


func _hex(color: Color) -> String:
	return "#%s" % color.to_html(false).to_upper()


func test_ember_palette_matches_design_board_contract() -> void:
	assert_eq(_hex(ThemeResource.get_color(&"background", &"PrimalNightPalette")), "#16130E")
	assert_eq(_hex(ThemeResource.get_color(&"surface", &"PrimalNightPalette")), "#262017")
	assert_eq(_hex(ThemeResource.get_color(&"body", &"PrimalNightPalette")), "#ECE3D2")
	assert_eq(_hex(ThemeResource.get_color(&"accent_amber", &"PrimalNightPalette")), "#E0A458")
	assert_eq(_hex(ThemeResource.get_color(&"equipment_cyan", &"PrimalNightPalette")), "#6FC7C9")


func test_stage_colors_use_three_theme_common_values() -> void:
	assert_eq(_hex(ThemeResource.get_color(&"stage_good", &"PrimalNightPalette")), "#8FA974")
	assert_eq(_hex(ThemeResource.get_color(&"stage_warn", &"PrimalNightPalette")), "#D9A441")
	assert_eq(_hex(ThemeResource.get_color(&"stage_danger", &"PrimalNightPalette")), "#D96A5C")


func test_hud_and_inventory_scenes_apply_shared_theme() -> void:
	var hud: Hud = HudScene.instantiate()
	var inventory: InventoryScreen = InventoryScreenScene.instantiate()
	add_child_autofree(hud)
	add_child_autofree(inventory)

	assert_eq((hud.get_node(^"Root") as Control).theme, ThemeResource)
	assert_eq((inventory.get_node(^"Root") as Control).theme, ThemeResource)


func test_shared_theme_uses_textured_panel_and_visible_keyboard_focus() -> void:
	assert_true(ThemeResource.get_stylebox(&"panel", &"PanelContainer") is StyleBoxTexture)
	assert_true(ThemeResource.get_stylebox(&"focus", &"Button") is StyleBoxFlat)
	assert_eq(ThemeResource.get_type_variation_base(&"TitleLabel"), &"Label")
	assert_eq(ThemeResource.get_type_variation_base(&"KeyPrompt"), &"Label")


func test_title_screen_binds_generated_night_valley_art() -> void:
	var title: TitleScreen = add_child_autofree(TitleScene.instantiate()) as TitleScreen
	var art := title.get_node("BackgroundArt") as TextureRect
	assert_not_null(art.texture)
	assert_eq(art.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	assert_eq((title.get_node("Center/MenuPanel/Content/Title") as Label).theme_type_variation,
		&"TitleLabel")


func test_boot_hides_performance_overlay_by_default_and_f3_restores_it() -> void:
	add_child_autofree(BootScene.instantiate())
	var overlay := add_child_autofree(PerformanceOverlayScene.instantiate()) as CanvasLayer
	await wait_process_frames(2)
	assert_false(overlay.visible, "commercial default keeps debug metrics hidden")
	assert_false(overlay.is_processing())
	var event := InputEventKey.new()
	event.keycode = KEY_F3
	event.pressed = true
	assert_true(overlay.handle_debug_toggle(event))
	assert_true(overlay.visible, "F3 remains an explicit developer toggle")
	assert_true(overlay.is_processing())

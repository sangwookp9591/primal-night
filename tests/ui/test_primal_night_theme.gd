extends GutTest

const ThemeResource: Theme = preload("res://scenes/ui/theme/primal_night_theme.tres")
const HudScene: PackedScene = preload("res://scenes/ui/hud/hud.tscn")
const InventoryScreenScene: PackedScene = preload("res://scenes/ui/inventory/inventory_screen.tscn")


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

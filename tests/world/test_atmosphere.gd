extends GutTest

const CampfireScene: PackedScene = preload("res://scenes/props/campfire.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func test_phase_palette_is_readable_and_ordered() -> void:
	var day := AtmosphereController.phase_color(SessionClock.Phase.DAYLIGHT, 120.0)
	var dawn := AtmosphereController.phase_color(SessionClock.Phase.DAYLIGHT, 0.0)
	var dusk := AtmosphereController.phase_color(SessionClock.Phase.DUSK)
	var night := AtmosphereController.phase_color(SessionClock.Phase.NIGHT)
	assert_eq(day, AtmosphereController.DAY_COLOR)
	assert_eq(dawn, AtmosphereController.DAWN_COLOR)
	assert_eq(dusk, AtmosphereController.DUSK_COLOR)
	assert_eq(night, AtmosphereController.NIGHT_COLOR)
	assert_gt(night.get_luminance(), 0.1, "밤도 완전 암전이면 안 된다")
	assert_lt(night.get_luminance(), day.get_luminance(), "밤은 낮보다 충분히 어두워야 한다")


func test_campfire_light_tracks_lit_state() -> void:
	var fire := add_child_autofree(CampfireScene.instantiate()) as Campfire
	var light := fire.get_node("WarmLight") as PointLight2D
	assert_false(light.enabled)
	assert_true(light.texture is GradientTexture2D, "GL compatibility용 런타임 2D 텍스처를 쓴다")
	fire.light()
	assert_true(light.enabled)
	fire.extinguish()
	assert_false(light.enabled)


func test_rain_slightly_reduces_atmosphere_luminance() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	var atmosphere := main.get_node("AtmosphereController") as AtmosphereController
	var weather := main.get_node("NetWeather") as NetWeather
	var dry := atmosphere.target_color()
	weather.apply_weather(true, 1.0)
	var rainy := atmosphere.target_color()
	assert_lt(rainy.get_luminance(), dry.get_luminance())
	assert_gt(rainy.get_luminance(), dry.get_luminance() * 0.8,
		"비 보정은 시인성을 무너뜨리지 않는 미세 조정이어야 한다")


func test_torch_light_follows_equipment_signal_for_spawned_and_respawned_players() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	var players := main.get_node("Players")
	var first := PlayerScene.instantiate() as Player
	first.name = "Remote"
	players.add_child(first)
	await wait_process_frames(2)
	assert_true(first.inventory.add_item(&"torch", 1) == 1)
	assert_true(first.equipment.request_equip(&"torch"))
	var light := first.get_node_or_null("HeldTorchLight") as PointLight2D
	assert_not_null(light)
	assert_true(light.enabled)
	assert_true(first.equipment.request_unequip(&"main_hand"))
	assert_false(light.enabled)

	first.queue_free()
	await wait_process_frames(2)
	var respawned := PlayerScene.instantiate() as Player
	respawned.name = "Remote"
	players.add_child(respawned)
	await wait_process_frames(2)
	assert_true(respawned.inventory.add_item(&"torch", 1) == 1)
	assert_true(respawned.equipment.request_equip(&"torch"))
	var respawned_light := respawned.get_node_or_null("HeldTorchLight") as PointLight2D
	assert_not_null(respawned_light)
	assert_true(respawned_light.enabled)


func test_main_atmosphere_is_visual_only_and_gl_compatible() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	assert_not_null(main.get_node_or_null("WorldTint"))
	assert_not_null(main.get_node_or_null("AtmosphereController"))
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")

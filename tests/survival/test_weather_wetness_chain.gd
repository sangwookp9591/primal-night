extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var player: Player
var weather: NetWeather

func before_each() -> void:
	var clock := SessionClock.new()
	clock.name = "Clock"
	get_tree().root.add_child(clock)
	weather = NetWeather.new()
	weather.name = "TestWeather"
	weather.clock_path = ^"../Clock"
	get_tree().root.add_child(weather)
	weather.raining = false
	weather.intensity = 0.0
	player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame

func after_each() -> void:
	if is_instance_valid(weather):
		weather.queue_free()
	var clock := get_tree().root.get_node_or_null("Clock")
	if clock != null:
		clock.queue_free()
	await get_tree().process_frame

func test_seeded_three_day_schedule_has_one_or_two_predictable_rains() -> void:
	var first := NetWeather.build_schedule(731941, 600.0, 3)
	var repeat := NetWeather.build_schedule(731941, 600.0, 3)
	assert_between(first.size(), 1, 2)
	assert_eq(first, repeat)
	for window: Vector2 in first:
		assert_almost_eq(window.y - window.x, NetWeather.RAIN_DURATION_SECONDS, 0.001)

func test_rain_wetness_temperature_stamina_and_noise_form_numeric_chain() -> void:
	var stats := player.stats
	stats.temperature = 80.0
	stats.wetness = 0.0
	weather.raining = true
	weather.intensity = 1.0
	stats.simulate(60.0)
	var wet_after_rain := stats.wetness
	assert_almost_eq(wet_after_rain, 0.45, 0.01,
		"흰 속옷: 0.006/s × 1.25 × 60s = 0.45")

	weather.raining = false
	var wet_temp_before := stats.temperature
	stats.simulate(10.0)
	var wet_temp_loss := wet_temp_before - stats.temperature
	stats.wetness = 0.0
	var dry_temp_before := stats.temperature
	stats.simulate(10.0)
	var dry_temp_loss := dry_temp_before - stats.temperature
	assert_gt(wet_temp_loss, dry_temp_loss)

	stats.wetness = wet_after_rain
	stats.apply_replicated(stats.temperature, stats.water, stats.food, stats.fatigue, wet_after_rain)
	player.stamina.current_stamina = 100.0
	player.stamina.update(true, true, 1.0, 0.0, 1.0, stats.wet_run_drain_penalty())
	var wet_stamina_loss := 100.0 - player.stamina.current_stamina
	player.stamina.current_stamina = 100.0
	player.stamina.update(true, true, 1.0)
	var dry_stamina_loss := 100.0 - player.stamina.current_stamina
	assert_gt(wet_stamina_loss, dry_stamina_loss)

	var dry_noise := player.config.run_noise_profile.radius
	var wet_noise := dry_noise * player.clothing_noise_multiplier()
	assert_gt(wet_noise, dry_noise)
	assert_true((player.equipment.condition_flags & SurvivalStats.WET_FLAG) != 0)

func test_outfits_have_tradeoffs_and_fire_dries_faster_than_air() -> void:
	var game_data := get_node("/root/GameData")
	var underwear := game_data.get_item(&"white_underwear") as WearableData
	var work := game_data.get_item(&"work_clothes") as WearableData
	var leather := game_data.get_item(&"leather_armor") as WearableData
	assert_gt(underwear.drying_speed, work.drying_speed)
	assert_gt(work.wet_weight_penalty, underwear.wet_weight_penalty)
	assert_gt(float(leather.modifiers.warmth), float(work.modifiers.warmth))
	assert_gt(leather.noise_modifier, work.noise_modifier)
	assert_gt(leather.smell_modifier, work.smell_modifier)

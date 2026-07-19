extends GutTest

const CampfireScene: PackedScene = preload("res://scenes/props/campfire.tscn")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")


func test_campfire_particles_follow_lit_and_smoky_states() -> void:
	var fire := add_child_autofree(CampfireScene.instantiate()) as Campfire
	var sparks := fire.get_node("SparkParticles") as CPUParticles2D
	var smoke := fire.get_node("SmokeParticles") as CPUParticles2D
	var embers := fire.get_node("EmberParticles") as CPUParticles2D
	assert_false(sparks.emitting)
	assert_false(smoke.emitting)
	assert_false(embers.emitting)
	fire.light()
	assert_true(sparks.emitting)
	assert_true(smoke.emitting)
	assert_true(embers.emitting)
	var dry_amount := smoke.amount
	fire.set_smoky(true)
	assert_gt(smoke.amount, dry_amount, "젖은 장작은 연기 입자가 강화되어야 한다")
	assert_lte(smoke.amount, 28, "모닥불 연기 성능 상한")
	fire.extinguish()
	assert_false(sparks.emitting)
	assert_false(smoke.emitting)


func test_running_emits_foot_dust_but_walking_does_not() -> void:
	var player := add_child_autofree(PlayerScene.instantiate()) as Player
	var effects := player.get_node("PlayerEffects") as PlayerEffects
	var dust := effects.get_node("FootDust") as CPUParticles2D
	player.stance = Player.Stance.RUN
	player.velocity = Vector2(80.0, 0.0)
	effects._process(0.016)
	assert_true(dust.emitting)
	assert_lte(dust.amount, PlayerEffects.MAX_DUST_PARTICLES)
	player.stance = Player.Stance.WALK
	effects._process(0.016)
	assert_false(dust.emitting)


func test_hit_effects_are_short_visual_only_bursts() -> void:
	var player := add_child_autofree(PlayerScene.instantiate()) as Player
	var effects := player.get_node("PlayerEffects") as PlayerEffects
	var melee := effects.get_node("MeleeImpact") as CPUParticles2D
	var arrow := effects.get_node("ArrowDebris") as CPUParticles2D
	effects.play_impact(&"arrow", Vector2(10.0, 12.0))
	assert_true(arrow.one_shot)
	assert_true(arrow.emitting)
	effects.play_impact(&"melee")
	assert_true(melee.one_shot)
	assert_true(melee.emitting)
	assert_lte(PlayerEffects.HITSTOP_SECONDS, 0.05)
	assert_false(get_tree().paused, "히트스톱은 판정 트리를 멈추면 안 된다")


func test_rain_particles_and_vignette_follow_weather_state() -> void:
	var root: Node = add_child_autofree(Node.new())
	var clock := SessionClock.new()
	clock.name = "Clock"
	root.add_child(clock)
	var weather := NetWeather.new()
	weather.clock_path = ^"../Clock"
	root.add_child(weather)
	var streaks := weather.get_node("RainStreaks") as CPUParticles2D
	var splashes := weather.get_node("RainSplashes") as CPUParticles2D
	var vignette := weather.get_node("WetVignette") as TextureRect
	weather.apply_weather(true, 0.8)
	assert_true(streaks.emitting)
	assert_true(splashes.emitting)
	assert_true(vignette.visible)
	assert_lte(streaks.amount, NetWeather.MAX_RAIN_STREAKS)
	assert_lte(splashes.amount, NetWeather.MAX_RAIN_SPLASHES)
	weather.apply_weather(false, 0.0)
	assert_false(streaks.emitting)
	assert_false(splashes.emitting)
	assert_false(vignette.visible)


func test_ambient_particles_switch_day_and_night_with_bounded_counts() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var player := Node2D.new()
	player.name = "Player"
	root.add_child(player)
	var clock := SessionClock.new()
	clock.name = "SessionClock"
	root.add_child(clock)
	var ambient := AmbientParticles.new()
	root.add_child(ambient)
	var motes := ambient.get_node("DayMotes") as CPUParticles2D
	var fireflies := ambient.get_node("NightFireflies") as CPUParticles2D
	assert_true(motes.emitting)
	assert_false(fireflies.emitting)
	clock.apply_replicated(1, clock.daylight_duration_seconds
		+ clock.dusk_duration_seconds + 1.0, true)
	assert_false(motes.emitting)
	assert_true(fireflies.emitting)
	assert_lte(motes.amount, AmbientParticles.MAX_DAY_MOTES)
	assert_lte(fireflies.amount, AmbientParticles.MAX_FIREFLIES)
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"gl_compatibility")

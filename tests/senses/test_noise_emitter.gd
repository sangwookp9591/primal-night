extends GutTest

const NoiseEmitterScript = preload("res://scripts/senses/noise_emitter.gd")
const NoiseProfileScript = preload("res://scripts/senses/noise_profile.gd")

const WALK_PROFILE: NoiseProfile = preload("res://data/senses/noise_walk.tres")
const RUN_PROFILE: NoiseProfile = preload("res://data/senses/noise_run.tres")
const BRUSH_PROFILE: NoiseProfile = preload("res://data/senses/noise_brush.tres")
const HARVEST_PROFILE: NoiseProfile = preload("res://data/senses/noise_harvest.tres")
const THROW_PROFILE: NoiseProfile = preload("res://data/senses/noise_throw.tres")
const CAMPFIRE_BUILD_PROFILE: NoiseProfile = preload("res://data/senses/noise_campfire_build.tres")
const INJURED_GROAN_PROFILE: NoiseProfile = preload("res://data/senses/noise_injured_groan.tres")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func test_required_noise_profiles_are_data_resources() -> void:
	var profiles: Array[NoiseProfile] = [
		WALK_PROFILE,
		RUN_PROFILE,
		BRUSH_PROFILE,
		HARVEST_PROFILE,
		THROW_PROFILE,
		CAMPFIRE_BUILD_PROFILE,
		INJURED_GROAN_PROFILE,
	]

	for profile: NoiseProfile in profiles:
		assert_not_null(profile)
		assert_ne(profile.id, &"", "행동별 소리는 데이터 id 를 가져야 한다")
		assert_gt(profile.radius, 0.0, "%s 반경은 0보다 커야 한다" % profile.id)
		assert_gt(profile.merge_window_seconds, 0.0, "%s 반복 병합 창이 있어야 한다" % profile.id)

func test_emits_noise_event_with_profile_radius_and_source() -> void:
	var emitter: NoiseEmitter = NoiseEmitterScript.new()
	var source: Node2D = add_child_autofree(Node2D.new())
	source.global_position = Vector2(64.0, 32.0)
	watch_signals(_event_bus)

	assert_true(emitter.emit_profile(_event_bus, HARVEST_PROFILE, source.global_position, source, 1.0))

	assert_signal_emitted(_event_bus, "noise_emitted")
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[0], source.global_position, "소리 위치는 발신 시점 좌표여야 한다")
	assert_eq(params[1], HARVEST_PROFILE.radius, "반경은 NoiseProfile 데이터에서 온다")
	assert_eq(params[2], source, "source 는 공정성 테스트용으로만 전달하고 추적 저장하지 않는다")

func test_same_profile_repeated_at_same_position_is_merged_inside_window() -> void:
	var emitter: NoiseEmitter = NoiseEmitterScript.new()
	var source: Node2D = add_child_autofree(Node2D.new())
	watch_signals(_event_bus)

	assert_true(emitter.emit_profile(_event_bus, BRUSH_PROFILE, Vector2.ZERO, source, 10.0))
	assert_false(emitter.emit_profile(_event_bus, BRUSH_PROFILE, Vector2(4.0, 0.0), source, 10.1),
		"같은 위치의 반복 소리는 짧은 창 안에서 병합되어야 한다")
	assert_true(emitter.emit_profile(_event_bus, BRUSH_PROFILE, Vector2.ZERO, source, 10.8),
		"병합 창이 지나면 다시 발신한다")

	assert_signal_emit_count(_event_bus, "noise_emitted", 2)

func test_authority_only_source_does_not_emit_from_non_authority_branch() -> void:
	var emitter: NoiseEmitter = NoiseEmitterScript.new()
	var source: Node2D = add_child_autofree(Node2D.new())
	source.set_multiplayer_authority(2)
	watch_signals(_event_bus)

	assert_false(emitter.emit_profile(_event_bus, RUN_PROFILE, Vector2.ZERO, source, 1.0, true))

	assert_signal_not_emitted(_event_bus, "noise_emitted",
		"소리 판정에 영향 주는 발신은 권위 브랜치에서만 나가야 한다")


func test_authority_only_rejects_null_source() -> void:
	var emitter: NoiseEmitter = NoiseEmitterScript.new()
	watch_signals(_event_bus)

	assert_false(emitter.emit_profile(_event_bus, THROW_PROFILE, Vector2.ZERO, null, 1.0, true))

	assert_signal_not_emitted(_event_bus, "noise_emitted",
		"권위 발신은 null source 로 우회할 수 없어야 한다")

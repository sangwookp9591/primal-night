extends GutTest

const RemoteNoiseLureScript = preload("res://scripts/items/remote_noise_lure.gd")
const LureNoise: NoiseProfile = preload("res://data/senses/noise_lure.tres")

var _event_bus: Node


func before_each() -> void:
	_event_bus = get_node("/root/EventBus")


func test_authority_can_install_and_remote_trigger_large_noise_once() -> void:
	var lure: Node2D = RemoteNoiseLureScript.new()
	add_child_autofree(lure)
	var source := Node.new()
	add_child_autofree(source)
	watch_signals(_event_bus)

	assert_true(lure.install_at(Vector2(320.0, 240.0), source))
	assert_true(lure.remote_trigger(source))
	assert_signal_emit_count(_event_bus, "noise_emitted", 1)
	var params: Array = get_signal_parameters(_event_bus, "noise_emitted", 0)
	assert_eq(params[0], Vector2(320.0, 240.0))
	assert_eq(params[1], LureNoise.radius)
	assert_gt(LureNoise.radius, preload("res://data/senses/noise_throw.tres").radius)
	assert_false(lure.remote_trigger(source), "소진성 스마트폰 미끼는 한 번만 울려야 한다")


func test_uninstalled_or_non_authority_trigger_is_rejected() -> void:
	var lure: Node2D = RemoteNoiseLureScript.new()
	add_child_autofree(lure)
	var source := Node.new()
	add_child_autofree(source)
	watch_signals(_event_bus)

	assert_false(lure.remote_trigger(source))
	source.set_multiplayer_authority(2)
	assert_false(lure.install_at(Vector2(10.0, 20.0), source))
	assert_signal_not_emitted(_event_bus, "noise_emitted")


func test_delayed_trigger_uses_host_authority() -> void:
	var lure: Node2D = RemoteNoiseLureScript.new()
	lure.trigger_delay_seconds = 0.01
	add_child_autofree(lure)
	var source := Node.new()
	add_child_autofree(source)
	watch_signals(_event_bus)

	assert_true(lure.install_at(Vector2(50.0, 60.0), source, true))
	await wait_physics_frames(5)
	assert_true(lure.spent, "지연 타이머가 권위 발동을 완료해야 한다")
	assert_signal_emit_count(_event_bus, "noise_emitted", 1)

extends GutTest

const OverlayScript = preload("res://scripts/debug/performance_overlay.gd")

func test_records_frame_ms_without_growing_sample_buffer() -> void:
	var overlay: CanvasLayer = autofree(OverlayScript.new())
	overlay.sample_capacity = 3
	overlay._ready()

	overlay.record_frame_ms(10.0)
	overlay.record_frame_ms(20.0)
	overlay.record_frame_ms(30.0)
	overlay.record_frame_ms(40.0)

	assert_eq(overlay.get_recorded_sample_count(), 3)
	assert_eq(overlay.get_recorded_frame_ms(), PackedFloat64Array([20.0, 30.0, 40.0]))

func test_refresh_interval_throttles_text_updates() -> void:
	var overlay: CanvasLayer = autofree(OverlayScript.new())
	overlay.refresh_interval_sec = 0.25
	overlay._ready()

	overlay.record_frame_ms(16.0)
	var updated_first: bool = overlay.maybe_refresh(0.10)
	var updated_second: bool = overlay.maybe_refresh(0.15)

	assert_false(updated_first)
	assert_true(updated_second)

func test_f3_key_event_toggles_visibility_once() -> void:
	var overlay: CanvasLayer = autofree(OverlayScript.new())
	overlay._ready()
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F3
	event.pressed = true

	var toggled: bool = overlay.handle_debug_toggle(event)

	assert_true(toggled)
	assert_false(overlay.visible)

func test_hidden_overlay_does_not_record_or_refresh_in_process() -> void:
	var overlay: CanvasLayer = autofree(OverlayScript.new())
	overlay.refresh_interval_sec = 0.01
	overlay._ready()
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F3
	event.pressed = true
	overlay.handle_debug_toggle(event)

	overlay._process(1.0)

	assert_eq(overlay.get_recorded_sample_count(), 0)
	assert_eq(overlay._refresh_elapsed_sec, 0.0)

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

extends GutTest

const FrameMetricsScript = preload("res://scripts/debug/frame_metrics.gd")

func test_summarizes_frame_times_with_percentiles_and_low_fps() -> void:
	var calculator: RefCounted = FrameMetricsScript.new()
	var samples: PackedFloat64Array = PackedFloat64Array([10.0, 12.0, 14.0, 16.0, 100.0])

	var summary: Dictionary = calculator.summarize(samples)

	assert_eq(summary["count"], 5)
	assert_eq(summary["frame_ms"]["p50"], 14.0)
	assert_eq(summary["frame_ms"]["p95"], 100.0)
	assert_eq(summary["frame_ms"]["p99"], 100.0)
	assert_eq(summary["stalls"]["over_33ms"], 1)
	assert_almost_eq(summary["fps"]["low_1_percent"], 10.0, 0.01)

func test_empty_input_returns_zeroed_summary() -> void:
	var calculator: RefCounted = FrameMetricsScript.new()

	var summary: Dictionary = calculator.summarize(PackedFloat64Array())

	assert_eq(summary["count"], 0)
	assert_eq(summary["frame_ms"]["p95"], 0.0)
	assert_eq(summary["fps"]["average"], 0.0)

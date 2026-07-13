extends GutTest

const PerfMonitorScript = preload("res://scripts/core/perf_monitor.gd")

func test_records_average_sample_time_and_key() -> void:
	var monitor: Node = autofree(PerfMonitorScript.new())

	monitor.begin_sample(&"unit")
	await wait_process_frames(2)
	monitor.end_sample(&"unit")

	assert_gt(monitor.get_avg_ms(&"unit"), 0.0)
	assert_has(monitor.get_keys(), &"unit")

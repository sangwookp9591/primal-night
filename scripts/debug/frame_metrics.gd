extends RefCounted

func summarize(frame_ms: PackedFloat64Array) -> Dictionary:
	var count: int = frame_ms.size()
	if count == 0:
		return {
			"count": 0,
			"frame_ms": {"p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0},
			"fps": {"average": 0.0, "low_1_percent": 0.0, "low_0_1_percent": 0.0},
			"stalls": {"over_33ms": 0, "over_50ms": 0, "over_100ms": 0},
		}

	var sorted_ms: PackedFloat64Array = frame_ms.duplicate()
	sorted_ms.sort()

	var total_ms: float = 0.0
	var over_33ms: int = 0
	var over_50ms: int = 0
	var over_100ms: int = 0
	for value_ms: float in sorted_ms:
		total_ms += value_ms
		if value_ms > 33.3:
			over_33ms += 1
		if value_ms > 50.0:
			over_50ms += 1
		if value_ms > 100.0:
			over_100ms += 1

	var average_frame_ms: float = total_ms / float(count)
	return {
		"count": count,
		"frame_ms": {
			"p50": _percentile(sorted_ms, 0.50),
			"p95": _percentile(sorted_ms, 0.95),
			"p99": _percentile(sorted_ms, 0.99),
			"max": sorted_ms[count - 1],
		},
		"fps": {
			"average": _fps_from_ms(average_frame_ms),
			"low_1_percent": _fps_from_ms(_tail_average_ms(sorted_ms, 0.01)),
			"low_0_1_percent": _fps_from_ms(_tail_average_ms(sorted_ms, 0.001)),
		},
		"stalls": {
			"over_33ms": over_33ms,
			"over_50ms": over_50ms,
			"over_100ms": over_100ms,
		},
	}

## p95 정의의 단일 소유자 — PerfMonitor 도 이걸 쓴다. 두 곳의 정의가 갈리면 안 된다.
static func _percentile(sorted_ms: PackedFloat64Array, percentile: float) -> float:
	var count: int = sorted_ms.size()
	var index: int = int(ceil(float(count) * percentile)) - 1
	return sorted_ms[clampi(index, 0, count - 1)]

func _tail_average_ms(sorted_ms: PackedFloat64Array, fraction: float) -> float:
	var count: int = sorted_ms.size()
	var tail_count: int = maxi(1, int(ceil(float(count) * fraction)))
	var total_ms: float = 0.0
	for index: int in range(count - tail_count, count):
		total_ms += sorted_ms[index]
	return total_ms / float(tail_count)

func _fps_from_ms(value_ms: float) -> float:
	if value_ms <= 0.0:
		return 0.0
	return 1000.0 / value_ms

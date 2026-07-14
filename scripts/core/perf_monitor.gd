extends Node

const SAMPLE_COUNT: int = 60
const FrameMetricsScript: Script = preload("res://scripts/debug/frame_metrics.gd")

var _keys: Array[StringName] = []
var _samples_by_key: Dictionary = {}
var _starts_by_key: Dictionary = {}
var _index_by_key: Dictionary = {}
var _count_by_key: Dictionary = {}
var _sum_by_key: Dictionary = {}

func begin_sample(key: StringName) -> void:
	_ensure_key(key)
	_starts_by_key[key] = Time.get_ticks_usec()

func end_sample(key: StringName) -> void:
	if not _starts_by_key.has(key):
		return

	var elapsed_ms: float = float(Time.get_ticks_usec() - int(_starts_by_key[key])) / 1000.0
	var samples: PackedFloat64Array = _samples_by_key[key]
	var index: int = int(_index_by_key[key])
	var count: int = int(_count_by_key[key])
	var sum: float = float(_sum_by_key[key])

	if count == SAMPLE_COUNT:
		sum -= samples[index]
	else:
		count += 1

	samples[index] = elapsed_ms
	sum += elapsed_ms
	_samples_by_key[key] = samples
	_index_by_key[key] = (index + 1) % SAMPLE_COUNT
	_count_by_key[key] = count
	_sum_by_key[key] = sum

func get_avg_ms(key: StringName) -> float:
	var count: int = int(_count_by_key.get(key, 0))
	if count == 0:
		return 0.0
	return float(_sum_by_key[key]) / float(count)


## 회귀 판정은 평균이 아니라 꼬리로 한다 (성능문서 4.2/10: 예산·회귀는 전부 p95 기준).
## 평균만 보면 60프레임 중 한 번 터지는 스파이크가 그대로 통과한다.
## 없는 키는 0 이 아니라 "계측 없음" 이지만, 0 을 돌려도 예산 통과로 오독되지 않게
## get_sample_count() 로 계측 존재 여부를 따로 확인한다 (tests/perf/test_sense_loop_budget.gd).
func get_p95_ms(key: StringName) -> float:
	return _percentile_ms(key, 0.95)


func get_max_ms(key: StringName) -> float:
	var window: PackedFloat64Array = _window(key)
	if window.is_empty():
		return 0.0
	return window[window.size() - 1]


func get_sample_count(key: StringName) -> int:
	return int(_count_by_key.get(key, 0))


## 한 키의 샘플을 버린다. 콜드스타트(첫 AI 틱의 내비 맵 준비, 첫 냄새 틱)를 워밍업으로
## 흘려보낸 뒤 정상 상태만 재는 데 쓴다 — 샘플이 적을 때는 p95 가 사실상 최대값이라,
## 콜드스타트를 섞으면 예산 게이트가 정상 상태가 아니라 기동 비용을 재게 된다.
func reset(key: StringName) -> void:
	if not _samples_by_key.has(key):
		return
	_index_by_key[key] = 0
	_count_by_key[key] = 0
	_sum_by_key[key] = 0.0

func get_keys() -> Array[StringName]:
	return _keys.duplicate()

## 링 버퍼에서 유효 샘플만 꺼내 정렬한다. 표시·기준선 캡처 경로에서만 부르는
## 호출이므로(프레임당 0회) 정렬 비용은 예산에 들어가지 않는다.
func _window(key: StringName) -> PackedFloat64Array:
	var count: int = int(_count_by_key.get(key, 0))
	if count == 0:
		return PackedFloat64Array()
	var samples: PackedFloat64Array = _samples_by_key[key]
	var window: PackedFloat64Array = samples.slice(0, count)
	window.sort()
	return window


func _percentile_ms(key: StringName, percentile: float) -> float:
	var window: PackedFloat64Array = _window(key)
	if window.is_empty():
		return 0.0
	# p95 정의는 FrameMetrics 가 소유한다 — 기준선 비교 가능성이 여기 걸려 있다.
	return FrameMetricsScript._percentile(window, percentile)


func _ensure_key(key: StringName) -> void:
	if _samples_by_key.has(key):
		return

	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(SAMPLE_COUNT)
	_samples_by_key[key] = samples
	_starts_by_key[key] = 0
	_index_by_key[key] = 0
	_count_by_key[key] = 0
	_sum_by_key[key] = 0.0
	_keys.append(key)

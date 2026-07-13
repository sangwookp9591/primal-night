extends Node

const SAMPLE_COUNT: int = 60

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

func get_keys() -> Array[StringName]:
	return _keys.duplicate()

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

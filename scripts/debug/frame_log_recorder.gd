extends RefCounted

var _frames: PackedFloat64Array = PackedFloat64Array()

func record_frame(frame_ms: float) -> void:
	_frames.append(frame_ms)

func get_frames() -> PackedFloat64Array:
	return _frames.duplicate()

func write_csv(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_line("frame,frame_ms")
	for index: int in range(_frames.size()):
		file.store_line("%d,%.3f" % [index, _frames[index]])
	return true

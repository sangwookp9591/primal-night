extends GutTest

const FrameLogRecorderScript = preload("res://scripts/debug/frame_log_recorder.gd")

func test_writes_frame_times_as_csv() -> void:
	var recorder: RefCounted = FrameLogRecorderScript.new()
	recorder.record_frame(16.5)
	recorder.record_frame(20.0)

	var path: String = "user://test_frame_log.csv"
	var ok: bool = recorder.write_csv(path)

	assert_true(ok)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file)
	assert_eq(file.get_as_text(), "frame,frame_ms\n0,16.500\n1,20.000\n")

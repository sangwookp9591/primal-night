extends GutTest

var _clock: SessionClock


func before_each() -> void:
	_clock = SessionClock.new()
	_clock.daylight_duration_seconds = 7.0
	_clock.dusk_duration_seconds = 1.0
	_clock.night_duration_seconds = 2.0
	_clock.total_days = 3
	add_child_autofree(_clock)


func test_starts_on_day_one_in_daylight() -> void:
	assert_eq(_clock.current_day, 1)
	assert_almost_eq(_clock.time_of_day_seconds, 0.0, 0.01)
	assert_eq(_clock.current_phase, 0)
	assert_true(_clock.running)


func test_advances_day_one_to_two_to_three() -> void:
	var days: Array[int] = []
	_clock.day_changed.connect(func(day: int) -> void: days.append(day))

	_clock.advance(10.0)
	_clock.advance(10.0)

	assert_eq(days, [2, 3])
	assert_eq(_clock.current_day, 3)
	assert_almost_eq(_clock.time_of_day_seconds, 0.0, 0.01)


func test_day_three_expiration_emits_exactly_once() -> void:
	watch_signals(_clock)

	_clock.advance(30.0)
	_clock.advance(10.0)

	assert_eq(_clock.current_day, 3)
	assert_almost_eq(_clock.time_of_day_seconds, 10.0, 0.01)
	assert_true(_clock.is_expired())
	assert_false(_clock.running)
	assert_signal_emit_count(_clock, "session_expired", 1)


func test_speed_multiplier_keeps_the_same_boundary_order() -> void:
	var normal: SessionClock = _make_clock(1.0)
	var fast: SessionClock = _make_clock(1.25)
	var normal_events: Array[String] = _capture_boundaries(normal)
	var fast_events: Array[String] = _capture_boundaries(fast)

	normal.advance(10.0)
	fast.advance(8.0)

	assert_eq(fast_events, normal_events)
	assert_eq(normal_events, ["phase:1", "phase:2", "day:2", "phase:0"])


func test_apply_replicated_restores_day_and_time_within_bounds() -> void:
	_clock.apply_replicated(2, 8.5, true)
	assert_eq(_clock.current_day, 2)
	assert_almost_eq(_clock.time_of_day_seconds, 8.5, 0.01)
	assert_eq(_clock.current_phase, 2)

	_clock.apply_replicated(99, 999.0, true)
	assert_eq(_clock.current_day, 3)
	assert_almost_eq(_clock.time_of_day_seconds, 10.0, 0.01)
	assert_false(_clock.running, "3일 종료 위치의 스냅샷은 다시 달릴 수 없다")

func test_ready_does_not_reset_state_applied_before_tree_entry() -> void:
	var restored := SessionClock.new()
	restored.apply_replicated(1, 77.2, true)
	add_child_autofree(restored)
	await wait_process_frames(2)
	assert_almost_eq(restored.time_of_day_seconds, 77.2, 0.2)
	assert_eq(restored.current_phase, SessionClock.Phase.DAYLIGHT)
	assert_almost_eq(restored.remaining_seconds,
		restored.session_duration_seconds() - 77.2, 0.2)


func _make_clock(speed: float) -> SessionClock:
	var clock: SessionClock = SessionClock.new()
	clock.daylight_duration_seconds = 7.0
	clock.dusk_duration_seconds = 1.0
	clock.night_duration_seconds = 2.0
	clock.total_days = 3
	clock.speed_multiplier = speed
	add_child_autofree(clock)
	return clock


func _capture_boundaries(clock: SessionClock) -> Array[String]:
	var events: Array[String] = []
	clock.phase_changed.connect(func(phase: int) -> void:
		events.append("phase:%d" % int(phase)))
	clock.day_changed.connect(func(day: int) -> void: events.append("day:%d" % day))
	return events

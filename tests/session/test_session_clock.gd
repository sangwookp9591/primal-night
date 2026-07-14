extends GutTest

## SessionClock — 회색 상자 루프의 초 단위 phase_time (계획서 W3-T2).
## 7일 세션 구조는 아직 만들지 않는다. 이 시계는 한 phase 의 남은 초만 센다.
## 시간의 권위는 호스트다 — 클라이언트도 같은 카운트다운을 돌려 화면을 채우지만,
## 호스트 스냅샷(LoopObjective.apply_session_snapshot)이 오면 그 값으로 덮인다.

var _clock: SessionClock


func before_each() -> void:
	_clock = SessionClock.new()
	_clock.phase_duration_seconds = 10.0
	add_child_autofree(_clock)


func test_clock_starts_running_at_full_phase_duration() -> void:
	assert_almost_eq(_clock.remaining_seconds, 10.0, 0.2, "시계는 phase 전체 시간에서 시작한다")
	assert_true(_clock.running, "세션이 시작되면 시계도 돈다")


func test_advance_counts_down_and_expires_exactly_once() -> void:
	watch_signals(_clock)

	_clock.advance(4.0)
	assert_almost_eq(_clock.remaining_seconds, 6.0, 0.2, "흐른 만큼 줄어든다")
	assert_false(_clock.is_expired(), "아직 만료가 아니다")

	_clock.advance(6.0)
	assert_true(_clock.is_expired(), "phase 시간이 다 되면 만료다")
	assert_false(_clock.running, "만료된 시계는 더 돌지 않는다")
	assert_signal_emit_count(_clock, "phase_expired", 1)

	_clock.advance(5.0)
	assert_almost_eq(_clock.remaining_seconds, 0.0, 0.01, "음수로 내려가지 않는다")
	assert_signal_emit_count(_clock, "phase_expired", 1, "만료 신호는 한 번만 나간다")


## 클라이언트 시계는 호스트 값으로 맞춰지되, 스스로 phase 를 늘려 잡을 수 없다.
func test_apply_replicated_takes_host_value_within_phase_bounds() -> void:
	_clock.apply_replicated(3.0, true)
	assert_almost_eq(_clock.remaining_seconds, 3.0, 0.01, "호스트 값으로 맞춘다")
	assert_true(_clock.running)

	_clock.apply_replicated(9999.0, true)
	assert_almost_eq(_clock.remaining_seconds, 10.0, 0.01, "phase 상한을 넘겨 시간을 벌 수 없다")

	_clock.apply_replicated(-5.0, false)
	assert_almost_eq(_clock.remaining_seconds, 0.0, 0.01, "음수 시간도 없다")
	assert_false(_clock.running)

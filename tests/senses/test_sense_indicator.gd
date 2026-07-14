extends GutTest

## 최소 감각 피드백 모델 (W3-T5, 설계서 5.4/12장 — 음소거 사용자도 위험 인지).
## 렌더와 분리된 순수 상태만 검증한다. 렌더 픽셀 검증은 하지 않는다.

const SenseIndicatorModelScript = preload("res://scripts/senses/sense_indicator_model.gd")

func _make_model() -> SenseIndicatorModel:
	return SenseIndicatorModelScript.new()

func test_wind_change_is_reflected_in_the_model() -> void:
	var model: SenseIndicatorModel = _make_model()
	assert_false(model.has_wind(), "초기 바람은 없어야 한다")

	model.set_wind(Vector2.RIGHT, 1.0)

	assert_true(model.has_wind(), "바람이 있으면 표시 대상이어야 한다")
	assert_eq(model.wind_direction, Vector2.RIGHT, "바람 방향을 그대로 반영해야 한다")
	assert_eq(model.wind_strength, 1.0, "바람 세기를 그대로 반영해야 한다")

func test_wind_calm_hides_the_indicator() -> void:
	var model: SenseIndicatorModel = _make_model()
	model.set_wind(Vector2.RIGHT, 1.0)

	model.set_wind(Vector2.RIGHT, 0.0)

	assert_false(model.has_wind(), "바람 세기가 0이면 표시하지 않는다")

func test_noise_records_direction_toward_the_source() -> void:
	var model: SenseIndicatorModel = _make_model()
	assert_false(model.has_recent_sound(), "초기에는 최근 소리가 없어야 한다")

	model.report_noise(Vector2(100.0, 0.0), Vector2.ZERO)

	assert_true(model.has_recent_sound(), "소리를 들으면 최근 소리 표시가 켜져야 한다")
	assert_eq(model.sound_direction(), Vector2.RIGHT, "소리 발생 지점 방향을 가리켜야 한다")

func test_noise_indicator_survives_before_the_duration_elapses() -> void:
	var model: SenseIndicatorModel = _make_model()
	model.report_noise(Vector2(100.0, 0.0), Vector2.ZERO)

	model.update(SenseIndicatorModelScript.SOUND_INDICATOR_SECONDS - 0.5)

	assert_true(model.has_recent_sound(), "지속 시간 전에는 사라지지 않는다")

func test_noise_indicator_fades_out_after_time() -> void:
	var model: SenseIndicatorModel = _make_model()
	model.report_noise(Vector2(100.0, 0.0), Vector2.ZERO)

	model.update(SenseIndicatorModelScript.SOUND_INDICATOR_SECONDS + 0.01)

	assert_false(model.has_recent_sound(), "시간이 지나면 최근 소리 표시가 사라져야 한다")
	assert_eq(model.sound_direction(), Vector2.ZERO, "사라진 뒤에는 방향도 비워야 한다")

func test_a_newer_sound_replaces_the_old_direction() -> void:
	var model: SenseIndicatorModel = _make_model()
	model.report_noise(Vector2(100.0, 0.0), Vector2.ZERO)
	model.update(SenseIndicatorModelScript.SOUND_INDICATOR_SECONDS - 0.5)

	model.report_noise(Vector2(0.0, -50.0), Vector2.ZERO)

	assert_eq(model.sound_direction(), Vector2.UP, "가장 최근 소리 방향으로 갱신되어야 한다")
	assert_true(model.has_recent_sound(), "새 소리로 지속 시간이 갱신되어야 한다")

func test_raptor_chase_entry_raises_the_alert() -> void:
	var model: SenseIndicatorModel = _make_model()
	assert_false(model.raptor_alert, "평상시에는 경보가 없어야 한다")

	model.set_raptor_chasing(true)

	assert_true(model.raptor_alert, "추격 진입 시 경보를 켜야 한다")

func test_raptor_losing_the_chase_clears_the_alert() -> void:
	var model: SenseIndicatorModel = _make_model()
	model.set_raptor_chasing(true)

	model.set_raptor_chasing(false)

	assert_false(model.raptor_alert, "추격을 벗어나면 경보를 꺼야 한다")

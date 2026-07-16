extends GutTest

## SensePlaytestRecorder — 재미 판정용 세션 recorder (계획서 W5-T3, §6.2).
## 예측 유효/적중 부등식, 채널 분리, 선택·전환 타임라인, 공정 경고, 종료 전 I/O 0회,
## 종료 JSON 스키마를 고정한다. 순수 집계는 명시 timestamp 로만 검증한다 (트리 밖).

const Recorder = preload("res://scripts/debug/sense_playtest_recorder.gd")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const HudScene: PackedScene = preload("res://scenes/ui/hud/hud.tscn")

const SOUND: StringName = &"sound"
const SMELL: StringName = &"smell"


## 트리 밖 순수 recorder — _ready 신호 연결·입력 폴링 없이 집계만 검증한다.
func _fresh() -> SensePlaytestRecorder:
	return autofree(Recorder.new())


func _keycode_bound(action: StringName, keycode: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and ((event as InputEventKey).keycode == keycode \
				or (event as InputEventKey).physical_keycode == keycode):
			return true
	return false


# ── InputMap 액션 + HUD 어포던스 ─────────────────────────────────────────────

func test_prediction_input_actions_exist_on_number_keys() -> void:
	assert_true(InputMap.has_action(&"predict_sound"), "predict_sound 액션이 있어야 한다")
	assert_true(InputMap.has_action(&"predict_smell"), "predict_smell 액션이 있어야 한다")
	assert_true(_keycode_bound(&"predict_sound", KEY_1), "predict_sound 는 키 1 이다")
	assert_true(_keycode_bound(&"predict_smell", KEY_2), "predict_smell 는 키 2 이다")


func test_hud_shows_prediction_controls_and_pending_marker() -> void:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var hud: Hud = HudScene.instantiate()
	world.add_child(hud)
	var recorder: SensePlaytestRecorder = Recorder.new()
	world.add_child(recorder)
	await wait_physics_frames(1)
	hud.bind(player)
	hud.bind_recorder(recorder)

	assert_true(hud.predict_visible(), "recorder 가 붙은 디버그 판에서는 예측 조작 행을 보인다")
	assert_string_contains(hud.predict_hint_text(), "1", "소리 예측 조작(1)을 안내한다")
	assert_string_contains(hud.predict_hint_text(), "2", "냄새 예측 조작(2)을 안내한다")

	assert_eq(hud.predict_pending_text(), "", "미결 표식이 없으면 비어 있다")
	recorder.on_prediction(SOUND, 1.0)
	hud._refresh_predict()
	assert_string_contains(hud.predict_pending_text(), "소리", "미결 예측 채널을 대기 표식으로 표시한다")


# ── 미결 표식: 채널당 1개 ────────────────────────────────────────────────────

func test_only_one_pending_marker_per_channel() -> void:
	var r: SensePlaytestRecorder = _fresh()
	r.on_prediction(SOUND, 1.0)
	r.on_prediction(SOUND, 2.0)  # 무시된다 — 채널당 미결 1개.
	r.on_clue(SOUND, 3.0)

	var report: Dictionary = r.build_report()
	assert_eq(report.predictions.size(), 1, "채널당 미결 표식은 1개만 기록된다")
	assert_eq(r.valid_count(), 1, "첫 미결 표식이 단서로 유효해진다")


func test_channels_are_tracked_separately() -> void:
	var r: SensePlaytestRecorder = _fresh()
	r.on_prediction(SOUND, 1.0)
	r.on_prediction(SMELL, 1.0)

	r.on_clue(SOUND, 2.0)
	assert_false(r.is_pending(SOUND), "소리 미결은 소리 단서로 소비된다")
	assert_true(r.is_pending(SMELL), "냄새 미결은 소리 단서로 소비되지 않는다")

	r.on_state_change(Raptor.State.INVESTIGATE, 3.0)  # 소리 적중
	r.on_clue(SMELL, 4.0)                              # 냄새 유효
	r.on_state_change(Raptor.State.INVESTIGATE, 5.0)  # 냄새 적중

	assert_eq(r.valid_count(SOUND), 1, "소리 유효 1")
	assert_eq(r.valid_count(SMELL), 1, "냄새 유효 1")
	assert_eq(r.hit_count(SOUND), 1, "소리 적중 1")
	assert_eq(r.hit_count(SMELL), 1, "냄새 적중 1")


# ── 유효/적중 부등식 경계값 ──────────────────────────────────────────────────

func test_validity_requires_clue_strictly_after_and_within_five_seconds() -> void:
	var exact: SensePlaytestRecorder = _fresh()
	exact.on_prediction(SOUND, 10.0)
	exact.on_clue(SOUND, 15.0)  # 정확히 +5초 → 유효 (<=)
	assert_eq(exact.valid_count(), 1, "단서가 예측 +5초 정확히면 유효")

	var late: SensePlaytestRecorder = _fresh()
	late.on_prediction(SOUND, 10.0)
	late.on_clue(SOUND, 15.001)  # +5초 초과 → 무효
	assert_eq(late.valid_count(), 0, "예측 +5초를 넘긴 단서는 무효")

	var simultaneous: SensePlaytestRecorder = _fresh()
	simultaneous.on_prediction(SOUND, 10.0)
	simultaneous.on_clue(SOUND, 10.0)  # 엄격 < 위반 → 무효
	assert_eq(simultaneous.valid_count(), 0, "예측과 동시 단서는 유효가 아니다")


func test_hit_requires_matching_transition_within_five_seconds_after_clue() -> void:
	var exact: SensePlaytestRecorder = _fresh()
	exact.on_prediction(SOUND, 1.0)
	exact.on_clue(SOUND, 2.0)
	exact.on_state_change(Raptor.State.INVESTIGATE, 7.0)  # 단서 +5초 정확 → 적중
	assert_eq(exact.hit_count(), 1, "단서 +5초 정확한 INVESTIGATE 전환은 적중")

	var late: SensePlaytestRecorder = _fresh()
	late.on_prediction(SOUND, 1.0)
	late.on_clue(SOUND, 2.0)
	late.on_state_change(Raptor.State.INVESTIGATE, 7.001)  # 창 초과 → 오답
	assert_eq(late.valid_count(), 1, "유효 표본으로는 남는다")
	assert_eq(late.hit_count(), 0, "창을 넘긴 전환은 오답")

	var wrong: SensePlaytestRecorder = _fresh()
	wrong.on_prediction(SOUND, 1.0)
	wrong.on_clue(SOUND, 2.0)
	wrong.on_state_change(Raptor.State.CHASE, 4.0)  # 다른 상태 → 오답
	assert_eq(wrong.valid_count(), 1, "유효 표본으로는 남는다")
	assert_eq(wrong.hit_count(), 0, "예측(INVESTIGATE)과 다른 전환은 오답")


func test_late_prediction_is_not_credited_to_an_earlier_clue() -> void:
	var r: SensePlaytestRecorder = _fresh()
	r.on_clue(SOUND, 1.0)                            # 단서가 먼저 (미결 예측 없음)
	r.on_prediction(SOUND, 2.0)                      # 단서 뒤 입력
	r.on_state_change(Raptor.State.INVESTIGATE, 3.0) # 대기 예측 없어 무관
	assert_eq(r.valid_count(), 0, "단서 뒤 입력한 예측은 이전 단서 적중으로 소급하지 않는다")

	r.on_clue(SOUND, 4.0)  # 예측 뒤 새 단서가 창 안(2<4<=7) → 이때 유효
	assert_eq(r.valid_count(), 1, "예측 뒤 새 단서가 창 안이면 그때 유효해진다")


# ── 선택·전환 타임라인 / 공정 경고 ────────────────────────────────────────────

func test_choice_and_following_transition_are_recorded_with_timing() -> void:
	var r: SensePlaytestRecorder = _fresh()
	r.on_choice(SensePlaytestRecorder.CHOICE_CROUCH, 5.0)
	r.on_state_change(Raptor.State.WANDER, 7.0)  # 웅크린 뒤 관심 상실

	var report: Dictionary = r.build_report()
	assert_eq(report.choices.size(), 1, "선택이 기록된다")
	assert_eq(StringName(report.choices[0].kind), SensePlaytestRecorder.CHOICE_CROUCH)
	assert_almost_eq(float(report.choices[0].at), 5.0, 0.001)
	assert_eq(report.raptor_transitions.size(), 1, "후속 전환도 타임라인에 남아 5초 창을 계산할 수 있다")
	assert_almost_eq(float(report.raptor_transitions[0].at), 7.0, 0.001)


func test_warning_time_from_chase_start_to_capture() -> void:
	var r: SensePlaytestRecorder = _fresh()
	r.on_state_change(Raptor.State.CHASE, 10.0)
	r.on_outcome(LoopObjective.Outcome.FAILED, 12.0)  # 포획
	assert_almost_eq(r.warning_time_before_capture(), 2.0, 0.001,
		"CHASE 시작부터 포획까지의 경고 시간을 잰다")

	var no_capture: SensePlaytestRecorder = _fresh()
	no_capture.on_state_change(Raptor.State.CHASE, 1.0)
	assert_eq(no_capture.warning_time_before_capture(), -1.0, "포획이 없으면 -1")


# ── 파일 I/O ─────────────────────────────────────────────────────────────────

func test_no_disk_write_before_session_end() -> void:
	var path: String = "user://test_recorder_no_early_io.json"
	_remove_user_file(path)

	var r: SensePlaytestRecorder = _fresh()
	r.on_prediction(SOUND, 1.0)
	r.on_clue(SOUND, 2.0)
	r.on_state_change(Raptor.State.INVESTIGATE, 3.0)

	assert_false(r.has_written(), "종료 전에는 디스크에 쓰지 않는다")
	assert_false(FileAccess.file_exists(path), "종료 전에는 산출 파일이 없다")

	assert_eq(r.write_session(path), OK, "세션 종료 쓰기는 성공한다")
	assert_true(FileAccess.file_exists(path), "종료 시 산출 파일이 생긴다")
	assert_true(r.has_written(), "쓰기 뒤 has_written 이 참이다")
	_remove_user_file(path)


func test_written_json_has_schema_version_and_required_prediction_fields() -> void:
	var path: String = "user://test_recorder_report.json"
	_remove_user_file(path)

	var r: SensePlaytestRecorder = _fresh()
	r.on_prediction(SOUND, 1.0)
	r.on_clue(SOUND, 2.0)                            # 유효
	r.on_state_change(Raptor.State.INVESTIGATE, 3.0) # 적중
	r.on_choice(SensePlaytestRecorder.CHOICE_CROUCH, 4.0)
	r.on_outcome(LoopObjective.Outcome.SUCCEEDED, 5.0)
	assert_eq(r.write_session(path), OK)

	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(data.schema_version), SensePlaytestRecorder.SCHEMA_VERSION, "스키마 버전을 담는다")
	for section: String in ["predictions", "clues", "raptor_transitions", "choices", "outcomes", "summary"]:
		assert_true(data.has(section), "산출 JSON 에 %s 섹션이 있어야 한다" % section)

	var prediction: Dictionary = data.predictions[0]
	for field: String in ["prediction_id", "channel", "predicted_next_state", "prediction_at",
			"clue_emitted_at", "state_changed_at", "valid", "hit", "invalid_reason"]:
		assert_true(prediction.has(field), "예측 레코드에 %s 필드가 있어야 한다" % field)

	assert_eq(int(data.summary.valid_total), 1, "요약의 유효 표본 수가 맞다")
	assert_eq(int(data.summary.hit_total), 1, "요약의 적중 수가 맞다")
	_remove_user_file(path)


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.open("user://").remove(path.get_file())

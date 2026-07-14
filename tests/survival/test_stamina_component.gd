extends GutTest

const StaminaComponentScript = preload("res://scripts/survival/stamina_component.gd")
const SurvivalConfigScript = preload("res://scripts/survival/survival_config.gd")

func _make_config() -> SurvivalConfig:
	var config: SurvivalConfig = SurvivalConfigScript.new()
	config.max_stamina = 100.0
	config.stamina_run_drain = 20.0
	config.stamina_regen_idle = 15.0
	config.stamina_regen_walk = 7.0
	config.stamina_recover_threshold = 20.0
	return config

func _make_stamina(config: SurvivalConfig) -> StaminaComponent:
	var stamina: StaminaComponent = StaminaComponentScript.new()
	stamina.config = config
	add_child_autofree(stamina)
	return stamina

func test_starts_at_max_stamina_and_can_run() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())
	assert_eq(stamina.current_stamina, 100.0, "초기 스태미나는 config.max_stamina 여야 한다")
	assert_true(stamina.can_run(), "가득 찬 상태에서는 달릴 수 있어야 한다")

func test_running_drains_stamina() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())

	stamina.update(true, true, 1.0)

	assert_almost_eq(stamina.current_stamina, 80.0, 0.001, "달리면 초당 stamina_run_drain 만큼 줄어야 한다")

func test_idle_regenerates_faster_than_walking() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())
	stamina.current_stamina = 50.0

	stamina.update(false, false, 1.0)
	assert_almost_eq(stamina.current_stamina, 65.0, 0.001, "정지 중에는 초당 stamina_regen_idle 만큼 회복해야 한다")

	stamina.current_stamina = 50.0
	stamina.update(false, true, 1.0)
	assert_almost_eq(stamina.current_stamina, 57.0, 0.001, "걷는 중에는 초당 stamina_regen_walk 만큼 회복해야 한다")

func test_regen_does_not_exceed_max() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())
	stamina.current_stamina = 95.0

	stamina.update(false, false, 10.0)

	assert_eq(stamina.current_stamina, 100.0, "회복은 max_stamina 를 넘을 수 없다")

func test_stamina_never_goes_negative() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())

	stamina.update(true, true, 60.0)

	assert_eq(stamina.current_stamina, 0.0, "스태미나는 음수가 될 수 없다")

## ★ 완료판정 2번: 스태미나 0 에서 달리기가 불가능하다.
func test_cannot_run_at_zero_stamina() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())

	stamina.update(true, true, 10.0)

	assert_eq(stamina.current_stamina, 0.0, "10초 달리면 소진된다")
	assert_false(stamina.can_run(), "스태미나 0 에서는 달릴 수 없어야 한다")

## 0 에서 걷기 회복이 시작되자마자 can_run 이 다시 참이 되면
## 프레임마다 달리기/걷기가 깜빡인다. 임계치까지는 잠겨 있어야 한다.
func test_exhaustion_locks_running_until_threshold_recovered() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())
	stamina.update(true, true, 10.0)
	assert_true(stamina.is_exhausted, "소진되면 탈진 상태여야 한다")

	# 걷기로 7.0 회복 -> 0 보다 크지만 임계치(20) 미만.
	stamina.update(false, true, 1.0)
	assert_gt(stamina.current_stamina, 0.0, "회복은 되고 있다")
	assert_false(stamina.can_run(), "임계치 아래에서는 아직 달릴 수 없어야 한다")

	# 임계치를 넘길 때까지 회복.
	stamina.update(false, false, 2.0)
	assert_gt(stamina.current_stamina, 20.0, "임계치를 넘겼다")
	assert_false(stamina.is_exhausted, "임계치를 넘기면 탈진이 풀려야 한다")
	assert_true(stamina.can_run(), "임계치를 넘기면 다시 달릴 수 있어야 한다")

## 탈진 상태에서 달리기 입력이 들어와도 스태미나를 더 깎지 않는다.
func test_exhausted_run_input_does_not_drain_further() -> void:
	var stamina: StaminaComponent = _make_stamina(_make_config())
	stamina.update(true, true, 10.0)

	stamina.update(true, true, 1.0)

	assert_gt(stamina.current_stamina, 0.0, "탈진 중 달리기 입력은 소모가 아니라 회복으로 처리되어야 한다")

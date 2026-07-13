extends GutTest

const HealthComponentScript = preload("res://scripts/survival/health_component.gd")
const SurvivalConfigScript = preload("res://scripts/survival/survival_config.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

## 테스트마다 수치를 명시해 .tres 튜닝이 테스트를 깨지 않게 한다.
func _make_config() -> SurvivalConfig:
	var config: SurvivalConfig = SurvivalConfigScript.new()
	config.max_health = 100.0
	config.bleed_damage_per_second = 2.0
	config.bleed_smell_interval = 0.5
	config.bleed_smell_strength = 60.0
	return config

## HealthComponent 는 Node2D 자식으로 붙는다 (냄새 발신에 global_position 이 필요).
func _make_health(config: SurvivalConfig) -> HealthComponent:
	var body: Node2D = add_child_autofree(Node2D.new())
	body.global_position = Vector2(64.0, 32.0)
	var health: HealthComponent = HealthComponentScript.new()
	health.config = config
	body.add_child(health)
	return health

func test_starts_at_max_health() -> void:
	var health: HealthComponent = _make_health(_make_config())
	assert_eq(health.current_health, 100.0, "초기 체력은 config.max_health 여야 한다")
	assert_true(health.is_alive(), "초기 상태는 살아 있어야 한다")

func test_take_damage_reduces_health_and_emits_damage_taken() -> void:
	var health: HealthComponent = _make_health(_make_config())
	watch_signals(_event_bus)

	health.take_damage(30.0, &"claw")

	assert_eq(health.current_health, 70.0, "피해량만큼 체력이 줄어야 한다")
	assert_signal_emitted(_event_bus, "damage_taken", "damage_taken 이 발신되어야 한다")
	var params: Array = get_signal_parameters(_event_bus, "damage_taken", 0)
	assert_eq(params[1], 30.0, "피해량이 그대로 전달되어야 한다")
	assert_eq(params[2], &"claw", "피해 종류가 그대로 전달되어야 한다")

func test_health_never_goes_negative_and_dies_at_zero() -> void:
	var health: HealthComponent = _make_health(_make_config())
	assert_true(health.is_alive(), "다치기 전에는 살아 있어야 한다")

	health.take_damage(60.0)
	assert_true(health.is_alive(), "치명상이 아니면 살아 있어야 한다")

	health.take_damage(150.0)

	assert_eq(health.current_health, 0.0, "체력은 음수가 될 수 없다")
	assert_false(health.is_alive(), "체력 0 이면 죽은 것이다")

func test_heal_does_not_exceed_max() -> void:
	var health: HealthComponent = _make_health(_make_config())

	health.take_damage(10.0)
	health.heal(999.0)

	assert_eq(health.current_health, 100.0, "치료는 max_health 를 넘을 수 없다")

func test_start_bleeding_emits_bleeding_started() -> void:
	var health: HealthComponent = _make_health(_make_config())
	watch_signals(_event_bus)

	health.start_bleeding()

	assert_true(health.is_bleeding, "출혈 상태여야 한다")
	assert_signal_emitted(_event_bus, "bleeding_started", "bleeding_started 가 발신되어야 한다")

func test_bleeding_applies_damage_over_time() -> void:
	var health: HealthComponent = _make_health(_make_config())
	health.start_bleeding()

	# 초당 2.0 피해 * 3초 = 6.0
	health._process(1.0)
	health._process(1.0)
	health._process(1.0)

	assert_almost_eq(health.current_health, 94.0, 0.001, "출혈은 초당 bleed_damage_per_second 만큼 깎아야 한다")

## ★ 목표 장면의 전제: 출혈 중 피 냄새가 "주기적으로" 발신된다. T4 의 랩터가 이걸 듣는다.
func test_bleeding_emits_blood_smell_periodically() -> void:
	var health: HealthComponent = _make_health(_make_config())
	watch_signals(_event_bus)
	health.start_bleeding()

	# 주기 0.5초. 총 1.2초 경과 -> 2회 발신 (0.5, 1.0), 나머지 0.2 는 누적.
	health._process(0.4)
	assert_signal_emit_count(_event_bus, "smell_emitted", 0, "주기 전에는 발신하지 않는다 (매 프레임 발신 금지)")

	health._process(0.4)
	health._process(0.4)

	assert_signal_emit_count(_event_bus, "smell_emitted", 2, "0.5초 주기로 2회 발신되어야 한다")

	var params: Array = get_signal_parameters(_event_bus, "smell_emitted", 0)
	assert_eq(params[0], Vector2(64.0, 32.0), "냄새는 출혈자의 위치에서 발생한다")
	assert_eq(params[1], 60.0, "strength 는 config.bleed_smell_strength 에서 온다")
	assert_eq(params[2], &"blood", "kind 는 &\"blood\" 여야 한다")

func test_stop_bleeding_emits_bleeding_stopped_and_halts_damage_and_smell() -> void:
	var health: HealthComponent = _make_health(_make_config())
	health.start_bleeding()
	health._process(1.0)
	var health_after_bleed: float = health.current_health
	watch_signals(_event_bus)

	health.stop_bleeding()
	health._process(5.0)

	assert_false(health.is_bleeding, "지혈되어야 한다")
	assert_signal_emitted(_event_bus, "bleeding_stopped", "bleeding_stopped 가 발신되어야 한다")
	assert_eq(health.current_health, health_after_bleed, "지혈 후에는 지속 피해가 없어야 한다")
	assert_signal_emit_count(_event_bus, "smell_emitted", 0, "지혈 후에는 피 냄새가 나지 않아야 한다")

## _process 를 손으로 부르는 위 테스트들과 별개로, 엔진이 실제로 틱을 돌리는지 확인한다.
func test_bleeding_is_actually_ticked_by_the_engine() -> void:
	var config: SurvivalConfig = _make_config()
	config.bleed_smell_interval = 0.05
	var health: HealthComponent = _make_health(config)
	watch_signals(_event_bus)

	health.start_bleeding()
	await wait_seconds(0.4)

	assert_gt(get_signal_emit_count(_event_bus, "smell_emitted"), 1, "엔진 틱만으로도 피 냄새가 반복 발신되어야 한다")
	assert_lt(health.current_health, 100.0, "엔진 틱만으로도 출혈 피해가 들어가야 한다")

extends GutTest

## 목표 장면을 손으로 재현하기 위한 디버그 부상 수단.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const DebugHurtScript = preload("res://scripts/survival/debug_hurt.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func test_hurt_damages_the_player_and_starts_bleeding() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var debug: DebugHurt = DebugHurtScript.new()
	debug.damage = 25.0
	add_child_autofree(debug)
	watch_signals(_event_bus)

	debug.hurt(player)

	assert_eq(player.health.current_health, 75.0, "설정한 피해량만큼 다쳐야 한다")
	assert_true(player.health.is_bleeding, "다치면 출혈이 시작되어야 한다")
	assert_signal_emitted(_event_bus, "bleeding_started", "bleeding_started 가 발신되어야 한다")

## ★ 목표 장면의 전제: 다치면 피 냄새가 실제로 퍼진다.
func test_hurting_the_player_makes_blood_smell_reach_the_event_bus() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var debug: DebugHurt = DebugHurtScript.new()
	add_child_autofree(debug)

	debug.hurt(player)
	watch_signals(_event_bus)
	await wait_seconds(0.6)  # bleed_smell_interval 은 0.5초

	assert_signal_emitted(_event_bus, "smell_emitted", "다치면 피 냄새가 발신되어야 한다")
	var params: Array = get_signal_parameters(_event_bus, "smell_emitted", 0)
	assert_eq(params[2], &"blood", "냄새 종류는 blood 여야 한다 (T4 랩터가 듣는다)")

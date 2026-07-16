extends GutTest

## 붕대로 지혈한다. 동료가 길게 눌러 치료하며 치료 중 양쪽 이동이 제한된다 (설계서 5.2).
## 네트워크 동기화는 2주차. 지금은 로컬 기준.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _spawn_pair(distance: float) -> Array:
	var world: Node2D = add_child_autofree(Node2D.new())
	var healer: Player = PlayerScene.instantiate()
	var patient: Player = PlayerScene.instantiate()
	world.add_child(healer)
	world.add_child(patient)
	patient.position = Vector2(distance, 0.0)
	await wait_physics_frames(2)
	return [healer, patient]

func _hold_seconds(patient: Player) -> float:
	return patient.health.config.bandage_hold_seconds

func test_bleeding_patient_with_healer_holding_a_bandage_is_a_valid_target() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	var patient: Player = pair[1]
	patient.health.start_bleeding()
	healer.inventory.add_item(&"bandage", 1)

	var target: Node = healer.interactor.find_target()

	assert_not_null(target, "출혈 중인 동료를 상호작용 대상으로 찾아야 한다")
	assert_eq((target as HealTarget).get_parent(), patient, "대상은 환자의 HealTarget 이어야 한다")
	assert_gt(target.get_hold_seconds(), 0.0, "치료는 길게 눌러야 한다")

func test_healthy_patient_is_not_a_heal_target() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	healer.inventory.add_item(&"bandage", 1)

	assert_null(healer.interactor.find_target(), "출혈 중이 아니면 치료 대상이 아니다")

func test_cannot_heal_without_a_bandage() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	var patient: Player = pair[1]
	patient.health.start_bleeding()

	assert_null(healer.interactor.find_target(), "붕대가 없으면 치료할 수 없다")

## ★ 완료판정 2번: 붕대 사용 시 출혈이 멈추고 bleeding_stopped 가 발신된다.
func test_completed_hold_stops_bleeding_and_consumes_the_bandage() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	var patient: Player = pair[1]
	patient.health.start_bleeding()
	healer.inventory.add_item(&"bandage", 2)
	watch_signals(_event_bus)

	healer.interactor.begin()
	assert_true(patient.health.is_bleeding, "홀드를 시작한 것만으로는 아직 낫지 않는다")

	# 홀드 시간을 넘겨 완료시킨다.
	healer.interactor._process(_hold_seconds(patient) + 0.01)

	assert_false(patient.health.is_bleeding, "붕대를 다 감으면 출혈이 멈춰야 한다")
	assert_signal_emitted(_event_bus, "bleeding_stopped", "bleeding_stopped 가 발신되어야 한다")
	assert_eq(healer.inventory.count_of(&"bandage"), 1, "붕대 1개를 소비해야 한다")

func test_completed_bandage_clears_leg_laceration_together_with_bleeding() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	var patient: Player = pair[1]
	patient.injury.apply_host_leg_laceration(0.0)
	healer.inventory.add_item(&"bandage", 1)
	watch_signals(_event_bus)
	patient.health._process(patient.health.config.bleed_smell_interval)
	assert_signal_emit_count(_event_bus, "smell_emitted", 1,
		"지혈 전 다리 열상은 피 냄새를 내야 한다")

	healer.interactor.begin()
	healer.interactor._process(_hold_seconds(patient) + 0.01)
	patient.health._process(patient.health.config.bleed_smell_interval)

	assert_false(patient.health.is_bleeding, "붕대는 출혈을 멈춰야 한다")
	assert_false(patient.injury.has_leg_laceration(), "붕대는 다리 열상도 함께 해소해야 한다")
	assert_signal_emit_count(_event_bus, "smell_emitted", 1, "지혈 후 피 냄새는 멈춰야 한다")

## 지혈되면 피 냄새도 멈춘다 — 목표 장면의 뒷부분.
func test_healing_stops_the_blood_smell() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	var patient: Player = pair[1]
	patient.health.start_bleeding()
	healer.inventory.add_item(&"bandage", 1)

	healer.interactor.begin()
	healer.interactor._process(_hold_seconds(patient) + 0.01)
	watch_signals(_event_bus)
	patient.health._process(5.0)

	assert_signal_emit_count(_event_bus, "smell_emitted", 0, "지혈 후에는 피 냄새가 나지 않아야 한다")

## 치료 중에는 두 플레이어 모두 이동이 제한된다 (설계서 5.2).
func test_both_players_are_movement_locked_during_the_heal() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	var patient: Player = pair[1]
	patient.health.start_bleeding()
	healer.inventory.add_item(&"bandage", 1)

	healer.interactor.begin()

	assert_true(healer.movement_locked, "치료하는 쪽 이동이 잠겨야 한다")
	assert_true(patient.movement_locked, "치료받는 쪽 이동도 잠겨야 한다")

	healer.interactor._process(_hold_seconds(patient) + 0.01)

	assert_false(healer.movement_locked, "치료가 끝나면 풀려야 한다")
	assert_false(patient.movement_locked, "치료가 끝나면 풀려야 한다")

## 도중에 손을 떼면 치료가 취소된다. 붕대도 소비되지 않는다.
func test_cancelling_the_hold_does_not_heal_and_does_not_consume() -> void:
	var pair: Array = await _spawn_pair(24.0)
	var healer: Player = pair[0]
	var patient: Player = pair[1]
	patient.health.start_bleeding()
	healer.inventory.add_item(&"bandage", 1)

	healer.interactor.begin()
	healer.interactor._process(_hold_seconds(patient) * 0.5)
	healer.interactor.cancel()

	assert_true(patient.health.is_bleeding, "도중에 놓으면 낫지 않는다")
	assert_eq(healer.inventory.count_of(&"bandage"), 1, "취소하면 붕대를 소비하지 않는다")
	assert_false(healer.movement_locked, "취소하면 이동 제한이 풀려야 한다")
	assert_false(patient.movement_locked, "취소하면 이동 제한이 풀려야 한다")

## 자기 자신에게도 붕대를 쓸 수 있다 (혼자 플레이).
func test_player_can_bandage_themselves() -> void:
	var pair: Array = await _spawn_pair(400.0)  # 동료는 멀리 둔다
	var player: Player = pair[0]
	player.health.start_bleeding()
	player.inventory.add_item(&"bandage", 1)
	await wait_physics_frames(2)

	var target: Node = player.interactor.find_target()
	assert_not_null(target, "자기 자신의 HealTarget 을 찾을 수 있어야 한다")

	player.interactor.begin()
	player.interactor._process(_hold_seconds(player) + 0.01)

	assert_false(player.health.is_bleeding, "스스로 지혈할 수 있어야 한다")
	assert_eq(player.inventory.count_of(&"bandage"), 0, "붕대를 소비한다")

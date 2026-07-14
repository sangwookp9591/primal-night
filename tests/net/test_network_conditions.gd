extends GutTest

## RTT/손실 조건 판정 모델 — 실제 게임 로직 밖, SessionService 경계 안의 하네스용.


func test_rtt_100_loss_1_keeps_sync_and_reconnects_by_player_id() -> void:
	var result: Dictionary = NetworkConditionScenario.run({
		name = "rtt100_loss1",
		rtt_ms = 100,
		packet_loss_percent = 1,
		jitter_ms = 0,
		use_peer_id_reconnect_key = false,
	})
	assert_true(result["sync_passed"])
	assert_eq(result["progress_blocking_errors"], 0)
	assert_true(result["reconnect_passed"])
	assert_lte(result["max_sync_error_px"], result["sync_tolerance_px"])


func test_rtt_250_loss_5_keeps_sync_and_reconnects_by_player_id() -> void:
	var result: Dictionary = NetworkConditionScenario.run({
		name = "rtt250_loss5",
		rtt_ms = 250,
		packet_loss_percent = 5,
		jitter_ms = 30,
		use_peer_id_reconnect_key = false,
	})
	assert_true(result["sync_passed"])
	assert_eq(result["progress_blocking_errors"], 0)
	assert_true(result["reconnect_passed"])
	assert_lte(result["max_sync_error_px"], result["sync_tolerance_px"])


func test_mutation_peer_id_reconnect_key_is_caught() -> void:
	var result: Dictionary = NetworkConditionScenario.run({
		name = "mutation_peer_id_key",
		rtt_ms = 100,
		packet_loss_percent = 1,
		jitter_ms = 0,
		use_peer_id_reconnect_key = true,
	})
	assert_false(result["reconnect_passed"])
	assert_eq(result["reconnect_failure_reason"], &"reconnect_key_changed")

extends SceneTree

## 짧은 CI용 네트워크 조건 하네스.
## 긴 2시간 원격 테스트 대신 RTT/loss 큐를 결정적으로 축소해 진행 차단 0건을 판정한다.

const PROFILES: Array[Dictionary] = [
	{name = "RTT 100ms / loss 1%", rtt_ms = 100, packet_loss_percent = 1, jitter_ms = 0},
	{name = "RTT 250ms / loss 5%", rtt_ms = 250, packet_loss_percent = 5, jitter_ms = 30},
]


func _init() -> void:
	var failed: bool = false
	print("=== network conditions harness: CI short scenario (2h remote test 축소) ===")
	for profile: Dictionary in PROFILES:
		var result: Dictionary = NetworkConditionScenario.run(profile)
		print("%s: sync=%s error=%.1fpx tolerance=%.1fpx blockers=%d reconnect=%s delivered=%d basis=%s" % [
			result["name"],
			"PASS" if result["sync_passed"] else "FAIL",
			result["max_sync_error_px"],
			result["sync_tolerance_px"],
			result["progress_blocking_errors"],
			"PASS" if result["reconnect_passed"] else "FAIL",
			result["delivered_packets"],
			result["tolerance_basis"],
		])
		if not result["sync_passed"] or int(result["progress_blocking_errors"]) != 0 or not result["reconnect_passed"]:
			failed = true

	var mutation: Dictionary = NetworkConditionScenario.run({
		name = "mutation peer-id reconnect key",
		rtt_ms = 100,
		packet_loss_percent = 1,
		jitter_ms = 0,
		use_peer_id_reconnect_key = true,
	})
	print("mutation peer-id reconnect key: %s reason=%s" % [
		"RED" if not mutation["reconnect_passed"] else "MISS",
		mutation["reconnect_failure_reason"],
	])
	if mutation["reconnect_passed"]:
		failed = true

	print("=== network conditions harness %s ===" % ("FAILED" if failed else "PASSED"))
	quit(1 if failed else 0)

class_name NetworkConditionScenario
extends RefCounted

## 네트워크 조건 하네스용 결정적 지연/손실 큐.
## Godot 4.7 ENetMultiplayerPeer 는 deterministic RTT/loss injection 을 제공하지 않아
## 테스트 경계 안에서 최신값 스냅샷 전달만 모델링한다.

const PHYSICS_HZ: float = 60.0
const SNAPSHOT_INTERVAL_TICKS: int = 6
const WALK_TICKS: int = 72
const SETTLE_TICKS: int = 150
const SPEED_PX_PER_TICK: float = 3.0
const PLAYER_ID: StringName = &"76561198000000001"
const FIRST_PEER_ID: int = 200
const RECONNECT_PEER_ID: int = 301


static func run(profile: Dictionary) -> Dictionary:
	var rtt_ms: int = int(profile.get("rtt_ms", 0))
	var loss_percent: int = int(profile.get("packet_loss_percent", 0))
	var jitter_ms: int = int(profile.get("jitter_ms", 0))
	var use_peer_id_reconnect_key: bool = bool(profile.get("use_peer_id_reconnect_key", false))
	var tolerance: float = _sync_tolerance_px(rtt_ms, jitter_ms)
	var one_way_ticks: int = ceili(((float(rtt_ms) * 0.5) + float(jitter_ms)) / 1000.0 * PHYSICS_HZ)
	var total_ticks: int = WALK_TICKS + SETTLE_TICKS
	var host_position: Vector2 = Vector2.ZERO
	var client_position: Vector2 = Vector2.ZERO
	var host_view_of_client: Vector2 = Vector2.ZERO
	var client_view_of_host: Vector2 = Vector2.ZERO
	var deliveries: Array[Dictionary] = []
	var packet_index: int = 0
	var delivered_packets: int = 0

	for tick: int in range(total_ticks):
		if tick < WALK_TICKS:
			host_position.x += SPEED_PX_PER_TICK
			client_position.x += SPEED_PX_PER_TICK
		if tick % SNAPSHOT_INTERVAL_TICKS == 0:
			if not _drops_packet(packet_index, loss_percent):
				deliveries.append({
					tick = tick + one_way_ticks,
					host = host_position,
					client = client_position,
				})
			packet_index += 1
		for delivery: Dictionary in deliveries:
			if int(delivery["tick"]) == tick:
				client_view_of_host = delivery["host"]
				host_view_of_client = delivery["client"]
				delivered_packets += 1

	var host_error: float = client_view_of_host.distance_to(host_position)
	var client_error: float = host_view_of_client.distance_to(client_position)
	var max_error: float = maxf(host_error, client_error)
	var reconnect: Dictionary = _reconnect_result(use_peer_id_reconnect_key)
	var progress_errors: int = 0
	if delivered_packets == 0:
		progress_errors += 1
	if max_error > tolerance:
		progress_errors += 1

	return {
		name = String(profile.get("name", "")),
		rtt_ms = rtt_ms,
		packet_loss_percent = loss_percent,
		jitter_ms = jitter_ms,
		sync_tolerance_px = tolerance,
		max_sync_error_px = max_error,
		sync_passed = max_error <= tolerance,
		progress_blocking_errors = progress_errors,
		reconnect_passed = bool(reconnect["passed"]),
		reconnect_failure_reason = reconnect["reason"],
		tolerance_basis = "run_speed 180px/s * (RTT/2 + 10Hz snapshot + jitter) + 12px floor",
		delivered_packets = delivered_packets,
	}


static func _sync_tolerance_px(rtt_ms: int, jitter_ms: int) -> float:
	var seconds: float = ((float(rtt_ms) * 0.5) + 100.0 + float(jitter_ms)) / 1000.0
	return ceilf(180.0 * seconds + 12.0)


static func _drops_packet(packet_index: int, loss_percent: int) -> bool:
	if loss_percent <= 0:
		return false
	return ((packet_index * 37 + 11) % 100) < loss_percent


static func _reconnect_result(use_peer_id_key: bool) -> Dictionary:
	var before_key: Variant = FIRST_PEER_ID if use_peer_id_key else PLAYER_ID
	var after_key: Variant = RECONNECT_PEER_ID if use_peer_id_key else PLAYER_ID
	if before_key != after_key:
		return {passed = false, reason = &"reconnect_key_changed"}
	return {passed = true, reason = &""}

class_name NetTestPorts
extends RefCounted

const BASE_PORT: int = 20000
const PORTS_PER_PROCESS: int = 16
const PROCESS_BUCKETS: int = 2048
const MAX_PROBE_ATTEMPTS: int = 256


static func port_for(slot: int) -> int:
	assert(slot >= 0 and slot < PORTS_PER_PROCESS)
	var process_bucket: int = OS.get_process_id() % PROCESS_BUCKETS
	return BASE_PORT + process_bucket * PORTS_PER_PROCESS + slot


static func pick_available_port(slot: int) -> int:
	assert(slot >= 0 and slot < PORTS_PER_PROCESS)
	var process_bucket: int = OS.get_process_id() % PROCESS_BUCKETS
	for offset: int in range(MAX_PROBE_ATTEMPTS):
		var candidate: int = BASE_PORT \
			+ ((process_bucket + offset) % PROCESS_BUCKETS) * PORTS_PER_PROCESS \
			+ slot
		var probe: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		if probe.create_server(candidate, 1) == OK:
			probe.close()
			return candidate
	push_error("No available ENet test port found for slot %d" % slot)
	return port_for(slot)

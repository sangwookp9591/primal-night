extends SceneTree

## Host + 3 장기 안정성 관문. 네 개의 실제 main.tscn 브랜치를 한 SceneTree에서
## ENet 루프백으로 펌프하며 연결 수명, 이동, 인벤토리, 장비/외형, 세션 결과를 검사한다.
##
## 기본 관문은 400주기 또는 8분 중 먼저 충족되는 압축 soak다. SOAK_MINUTES를
## 지정하면 해당 실시간(physics_frame 기준) 동안 실행하며 최소 주기 제한은 두지 않는다.
##
## 종료 증가 상한은 object 12%, static memory 20%다. 4개 main 인스턴스의 리소스
## 캐시/ENet 버퍼가 초반에 안정화된 뒤 측정하므로 정상 변동(대체로 한 자릿수 %)의
## 두 배 이상을 허용하되, 반복마다 노드/패킷 버퍼가 남는 선형 누수는 조기에 잡는다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const NetTestRigScript = preload("res://tests/support/net_test_rig.gd")
const CLIENT_COUNT := 3
const DEFAULT_MINUTES := 8.0
const DEFAULT_CYCLES := 400
const POSITION_TOLERANCE_PX := 56.0
const OBJECT_GROWTH_LIMIT := 0.12
const MEMORY_GROWTH_LIMIT := 0.20
const RECONNECT_INTERVAL := 25
const EQUIPMENT_ITEMS: Array[StringName] = [&"stone_spear", &"bow"]
const CONSERVED_ITEMS: Array[StringName] = [
	&"white_underwear", &"stone_spear", &"bow", &"arrow", &"bandage",
]

var _rig: RefCounted
var _mains: Array[Node2D] = []
var _sessions: Array[LocalSessionService] = []
var _player_ids: Array[StringName] = []
var _cycle := 0
var _checks := 0
var _started_msec := 0
var _baseline_objects := 0.0
var _baseline_memory := 0.0
var _full_mode := false
var _target_minutes := DEFAULT_MINUTES


func _init() -> void:
	_rig = NetTestRigScript.new(self)
	_run()


func _run() -> void:
	await process_frame
	var requested := OS.get_environment("SOAK_MINUTES")
	if not requested.is_empty():
		_full_mode = true
		_target_minutes = maxf(requested.to_float(), 0.01)
	for index in range(CLIENT_COUNT + 1):
		var root := Node.new()
		root.name = "SoakMachine%d" % index
		get_root().add_child(root)
		set_multiplayer(SceneMultiplayer.new(), root.get_path())
		var main := MainScene.instantiate() as Node2D
		main.name = "Main"
		root.add_child(main)
		_mains.append(main)
		_sessions.append(main.get_node("NetSession"))
		for required: String in [
			"NetMovement", "NetEquipment", "NetCombat", "NetPickup", "NetSurvival",
			"NetCampfire", "LoopObjective", "Players", "Player",
		]:
			if main.get_node_or_null(required) == null:
				return _fail("cycle=0 machine=%d item=node/%s missing" % [index, required])

	if _rig.start_host(_sessions[0]) != OK:
		return _fail("cycle=0 machine=0 item=connect host start failed")
	_player_ids.append(_sessions[0].get_local_player_id())
	for index in range(1, CLIENT_COUNT + 1):
		if _rig.connect_client(_sessions[index], _sessions[0]) != OK:
			return _fail("cycle=0 machine=%d item=connect join failed" % index)
		if not await _wait_players(index + 1):
			return _fail("cycle=0 machine=%d item=connect host roster timeout" % index)
		_player_ids.append(_sessions[index].get_local_player_id())
	if not await _wait_all_avatars(4):
		return _fail("cycle=0 machine=-1 item=avatar initial convergence timeout")

	_seed_consistent_inventory()
	# Warm caches, initial reliable RPC queues, and renderer/server objects before leak baseline.
	for unused in range(30):
		await physics_frame
	_baseline_objects = Performance.get_monitor(Performance.OBJECT_COUNT)
	_baseline_memory = Performance.get_monitor(Performance.MEMORY_STATIC)
	_started_msec = Time.get_ticks_msec()
	_log("START mode=%s target_minutes=%.2f target_cycles=%d objects=%.0f memory=%.0f" % [
		"full" if _full_mode else "compressed", _target_minutes,
		0 if _full_mode else DEFAULT_CYCLES, _baseline_objects, _baseline_memory])

	while not _done():
		_cycle += 1
		_script_movement()
		_script_equipment()
		if _cycle % 8 == 0:
			_script_combat_pose()
		for unused in range(3):
			await physics_frame
		if _cycle % RECONNECT_INTERVAL == 0:
			if not await _reconnect_client(1 + (_cycle / RECONNECT_INTERVAL as int) % CLIENT_COUNT):
				return
		if not _validate_cycle():
			return

	if not _validate_growth():
		return
	_rig.disconnect_all()
	await process_frame
	for index in range(_sessions.size()):
		var peer := _sessions[index].multiplayer.multiplayer_peer
		if peer != null and not peer is OfflineMultiplayerPeer:
			return _fail("cycle=%d machine=%d item=leaked_peer active peer after cleanup" % [_cycle, index])
	if not _rig.assert_no_leaked_peers():
		return _fail("cycle=%d machine=-1 item=leaked_peer rig assertion" % _cycle)
	_log("PASS cycles=%d checks=%d elapsed_seconds=%.2f" % [_cycle, _checks, _elapsed_seconds()])
	quit(0)


func _done() -> bool:
	if _full_mode:
		return _elapsed_seconds() >= _target_minutes * 60.0
	return _cycle >= DEFAULT_CYCLES or _elapsed_seconds() >= DEFAULT_MINUTES * 60.0


func _script_movement() -> void:
	var phase := -1.0 if _cycle % 2 == 0 else 1.0
	for index in range(_mains.size()):
		var avatar := _owned_avatar(index)
		avatar.global_position += Vector2(phase * (2.0 + index), float(index % 2) * phase)


func _script_equipment() -> void:
	var owner := _cycle % _mains.size()
	var avatar := _owned_avatar(owner)
	var net := _mains[owner].get_node("NetEquipment") as NetEquipment
	match _cycle % 4:
		0:
			net.request_equip(avatar, &"stone_spear")
		1:
			net.request_unequip(avatar, &"main_hand")
		2:
			net.request_equip(avatar, &"bow")
		3:
			net.request_unequip(avatar, &"main_hand")


func _script_combat_pose() -> void:
	var owner := _cycle % _mains.size()
	var avatar := _owned_avatar(owner)
	var combat := _mains[owner].get_node("NetCombat") as NetCombat
	if avatar.equipment.get_equipped(&"main_hand") == &"stone_spear":
		combat.request_attack(avatar, Vector2.RIGHT)
	elif avatar.equipment.get_equipped(&"main_hand") == &"bow":
		combat.request_bow_aim(avatar, true, Vector2.RIGHT)
		combat.request_bow_aim(avatar, false, Vector2.RIGHT)


func _reconnect_client(index: int) -> bool:
	var player_id := _player_ids[index]
	_sessions[index].leave_session()
	if not await _rig.pump_until(func() -> bool:
		return _sessions[0].get_players().size() == CLIENT_COUNT, 5.0):
		_fail("cycle=%d machine=%d item=disconnect host did not observe leave" % [_cycle, index])
		return false
	if _rig.connect_client(_sessions[index], _sessions[0], player_id) != OK:
		_fail("cycle=%d machine=%d item=reconnect join failed" % [_cycle, index])
		return false
	if not await _wait_players(CLIENT_COUNT + 1) or not await _wait_all_avatars(4):
		_fail("cycle=%d machine=%d item=reconnect convergence timeout" % [_cycle, index])
		return false
	return true


func _validate_cycle() -> bool:
	var host := _mains[0]
	var host_objective := host.get_node("LoopObjective") as LoopObjective
	for machine_index in range(_mains.size()):
		var main := _mains[machine_index]
		var avatars := _avatars(main)
		if avatars.size() != 4:
			return _violation(machine_index, "avatar_count", "expected=4 actual=%d" % avatars.size())
		for player_id in _player_ids:
			var host_avatar := _avatar(host, player_id)
			var replica := _avatar(main, player_id)
			if host_avatar == null or replica == null:
				return _violation(machine_index, "avatar_presence", "player=%s" % player_id)
			if host_avatar.global_position.distance_to(replica.global_position) > POSITION_TOLERANCE_PX:
				return _violation(machine_index, "position", "player=%s host=%s replica=%s" % [
					player_id, host_avatar.global_position, replica.global_position])
			var host_inventory := _inventory_signature(host_avatar)
			var replica_inventory := _inventory_signature(replica)
			if host_inventory != replica_inventory:
				return _violation(machine_index, "inventory_conservation",
					"player=%s host={%s} replica={%s}" % [
						player_id, host_inventory, replica_inventory])
			if host_avatar.equipment.get_snapshot() != replica.equipment.get_snapshot():
				return _violation(machine_index, "equipment_snapshot", "player=%s" % player_id)
			if not _visual_matches(replica):
				return _violation(machine_index, "equipment_visual", "player=%s" % player_id)
		var objective := main.get_node("LoopObjective") as LoopObjective
		if objective.outcome != host_objective.outcome:
			return _violation(machine_index, "session_result", "snapshot differs")
		if machine_index == 0 and _sessions[0].multiplayer.get_peers().size() != CLIENT_COUNT:
			return _violation(machine_index, "leaked_peer", "host peers=%d" % _sessions[0].multiplayer.get_peers().size())
		_checks += 5
	return true


func _validate_growth() -> bool:
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC)
	var object_growth := _growth(_baseline_objects, objects)
	var memory_growth := _growth(_baseline_memory, memory)
	_checks += 2
	if object_growth > OBJECT_GROWTH_LIMIT:
		return _violation(-1, "object_growth", "baseline=%.0f end=%.0f growth=%.3f limit=%.3f" % [
			_baseline_objects, objects, object_growth, OBJECT_GROWTH_LIMIT])
	if memory_growth > MEMORY_GROWTH_LIMIT:
		return _violation(-1, "memory_growth", "baseline=%.0f end=%.0f growth=%.3f limit=%.3f" % [
			_baseline_memory, memory, memory_growth, MEMORY_GROWTH_LIMIT])
	_log("GUARD objects=%.0f growth=%.3f memory=%.0f growth=%.3f" % [
		objects, object_growth, memory, memory_growth])
	return true


func _seed_consistent_inventory() -> void:
	for player_id in _player_ids:
		for main in _mains:
			var avatar := _avatar(main, player_id)
			for item_id in EQUIPMENT_ITEMS:
				avatar.inventory.add_item(item_id, 1)
			avatar.inventory.add_item(&"arrow", 2)
			avatar.inventory.add_item(&"bandage", 1)


func _inventory_signature(avatar: Player) -> String:
	var parts: PackedStringArray = []
	for item_id in CONSERVED_ITEMS:
		var total := avatar.inventory.count_of(item_id)
		var snapshot := avatar.equipment.get_snapshot()
		for slot: StringName in EquipmentComponent.SLOTS:
			if StringName(snapshot[slot]) == item_id:
				total += 1
		parts.append("%s:%d" % [item_id, total])
	return "|".join(parts)


func _visual_matches(avatar: Player) -> bool:
	var snapshot := avatar.equipment.get_snapshot()
	return avatar.visual_rig.outfit.visible == (snapshot.outfit != &"") \
		and avatar.visual_rig.back.visible == (snapshot.back != &"") \
		and avatar.visual_rig.main_hand.visible == (snapshot.main_hand != &"")


func _owned_avatar(machine_index: int) -> Player:
	if machine_index == 0:
		return _mains[0].get_node("Player") as Player
	return _avatar(_mains[machine_index], _player_ids[machine_index])


func _avatar(main: Node2D, player_id: StringName) -> Player:
	if player_id == _player_ids[0]:
		return main.get_node("Player") as Player
	return main.get_node_or_null(NodePath("Players/%s" % player_id)) as Player


func _avatars(main: Node2D) -> Array[Player]:
	var result: Array[Player] = [main.get_node("Player") as Player]
	for child in main.get_node("Players").get_children():
		if child is Player:
			result.append(child)
	return result


func _wait_players(count: int) -> bool:
	return await _rig.pump_until(func() -> bool:
		return _sessions[0].get_players().size() == count, 10.0)


func _wait_all_avatars(count: int) -> bool:
	return await _rig.pump_until(func() -> bool:
		for main in _mains:
			if _avatars(main).size() != count:
				return false
		return true, 10.0)


func _elapsed_seconds() -> float:
	if _started_msec == 0:
		return 0.0
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _growth(baseline: float, current: float) -> float:
	return 0.0 if baseline <= 0.0 else maxf(0.0, (current - baseline) / baseline)


func _violation(machine: int, item: String, detail: String) -> bool:
	_fail("cycle=%d machine=%d item=%s %s" % [_cycle, machine, item, detail])
	return false


func _log(message: String) -> void:
	print("[four-player-soak] %s" % message)


func _fail(reason: String) -> void:
	_log("FAIL %s" % reason)
	_rig.disconnect_all()
	quit(1)

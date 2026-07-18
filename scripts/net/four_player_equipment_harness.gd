extends SceneTree

## 실제 main.tscn 네 브랜치와 ENet 루프백으로 host + 3 장비 권위를 검증한다.
## 각 참가자가 자기 의상 해제를 요청한 뒤 네 기계의 모든 장비/외형이 일치해야 한다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const NetTestRigScript = preload("res://tests/support/net_test_rig.gd")
const CLIENT_COUNT: int = 3

var _rig: RefCounted
var _frames: int = 0


func _init() -> void:
	_rig = NetTestRigScript.new(self)
	_run()


func _run() -> void:
	await process_frame
	var roots: Array[Node] = []
	var mains: Array[Node2D] = []
	for index: int in range(CLIENT_COUNT + 1):
		var root := _make_machine("EquipmentMachine%d" % index)
		roots.append(root)
		mains.append(root.get_node("Main"))
		for required: String in ["NetSession", "NetMovement", "NetEquipment", "Players", "Player"]:
			if mains[index].get_node_or_null(required) == null:
				return _fail("machine=%d main.tscn 필수 노드 누락: %s" % [index, required])

	var host_session: LocalSessionService = mains[0].get_node("NetSession")
	if _rig.start_host(host_session) != OK:
		return _fail("호스트 개설 실패")

	var client_ids: Array[StringName] = []
	for index: int in range(1, CLIENT_COUNT + 1):
		var session: LocalSessionService = mains[index].get_node("NetSession")
		if _rig.connect_client(session, host_session) != OK:
			return _fail("client %d 참가 실패" % index)
		if not await _wait_until(func() -> bool:
			return host_session.get_players().size() == index + 1, 10.0):
			return _fail("client %d 참가를 호스트가 관측하지 못함" % index)
		client_ids.append(session.get_local_player_id())

	if not await _wait_until(func() -> bool:
		for machine: Node2D in mains:
			for player_id: StringName in client_ids:
				if not machine.has_node(NodePath("Players/%s" % player_id)):
					return false
		return true, 10.0):
		return _fail("네 기계에 세 원격 아바타가 모두 스폰되지 않음")

	# 호스트와 세 클라이언트가 각각 자기 장비만 변경한다.
	var host_net: NetEquipment = mains[0].get_node("NetEquipment")
	var host_player: Player = mains[0].get_node("Player")
	if not host_net.request_unequip(host_player, &"outfit"):
		return _fail("호스트 의상 해제 확정 실패")
	for index: int in range(CLIENT_COUNT):
		var machine: Node2D = mains[index + 1]
		var net: NetEquipment = machine.get_node("NetEquipment")
		var avatar: Player = machine.get_node(NodePath("Players/%s" % client_ids[index]))
		if not net.request_unequip(avatar, &"outfit"):
			return _fail("client %d 의상 해제 의도 전송 실패" % (index + 1))

	if not await _wait_until(func() -> bool:
		for machine: Node2D in mains:
			if not _is_unequipped(machine.get_node("Player")):
				return false
			for player_id: StringName in client_ids:
				var avatar: Player = machine.get_node(NodePath("Players/%s" % player_id))
				if not _is_unequipped(avatar):
					return false
		return true, 10.0):
		return _fail("전 피어 장비 스냅샷/외형이 호스트 확정 상태로 수렴하지 않음")

	_log("PASS host+3: 4명 각자 변경 → 4개 기계의 16개 아바타 장비/외형 일치")
	_rig.disconnect_all()
	if not _rig.assert_no_leaked_peers():
		return _fail("NetTestRig peer 누수")
	quit(0)


func _is_unequipped(avatar: Player) -> bool:
	return avatar.equipment.get_equipped(&"outfit") == &"" \
		and not avatar.visual_rig.outfit.visible


func _make_machine(machine_name: String) -> Node:
	var root := Node.new()
	root.name = machine_name
	get_root().add_child(root)
	set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var main: Node2D = MainScene.instantiate()
	main.name = "Main"
	root.add_child(main)
	return root


func _wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var result: bool = await _rig.pump_until(condition, timeout_seconds)
	_frames += int(timeout_seconds * 60.0) if not result else 1
	return result


func _log(message: String) -> void:
	print("[four-player-equipment] %s" % message)


func _fail(reason: String) -> void:
	_log("FAIL: %s" % reason)
	_rig.disconnect_all()
	quit(1)

extends SceneTree

## 실제 main.tscn 두 브랜치와 ENet 루프백으로 클라이언트 공격 의도부터
## 호스트 체력 확정, 사망, 양쪽 사체 생성까지 검증한다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const NetTestRigScript = preload("res://tests/support/net_test_rig.gd")
var _rig: RefCounted

func _init() -> void:
	_rig = NetTestRigScript.new(self)
	_run()

func _run() -> void:
	await process_frame
	var host_root := _make_machine("CombatHost")
	var client_root := _make_machine("CombatClient")
	var host: Node2D = host_root.get_node("Main")
	var client: Node2D = client_root.get_node("Main")
	var host_session: LocalSessionService = host.get_node("NetSession")
	var client_session: LocalSessionService = client.get_node("NetSession")
	if _rig.start_host(host_session) != OK \
			or _rig.connect_client(client_session, host_session) != OK:
		return _fail("host+1 연결 실패")
	if not await _rig.pump_until(func() -> bool:
		var id := client_session.get_local_player_id()
		return id != &"" and host.has_node(NodePath("Players/%s" % id)) \
			and client.has_node(NodePath("Players/%s" % id)), 10.0):
		return _fail("클라이언트 아바타 스폰 실패")
	var player_id := client_session.get_local_player_id()
	var host_avatar: Player = host.get_node(NodePath("Players/%s" % player_id))
	var client_avatar: Player = client.get_node(NodePath("Players/%s" % player_id))
	host_avatar.inventory.add_item(&"bow", 1)
	host_avatar.inventory.add_item(&"arrow", 1)
	var client_equipment: NetEquipment = client.get_node("NetEquipment")
	if not client_equipment.request_equip(client_avatar, &"bow"):
		return _fail("클라이언트 활 장착 의도 전송 실패")
	if not await _rig.pump_until(func() -> bool:
		return host_avatar.equipment.get_equipped(&"main_hand") == &"bow" \
			and client_avatar.equipment.get_equipped(&"main_hand") == &"bow", 5.0):
		return _fail("활 장착 복제 실패")
	var host_raptor: Raptor = host.get_node("Raptor")
	var client_raptor: Raptor = client.get_node("Raptor")
	host_raptor.global_position = host_avatar.global_position + Vector2(260, 0)
	client_raptor.global_position = client_avatar.global_position + Vector2(260, 0)
	host_raptor.move_target = host_raptor.global_position
	client_raptor.move_target = client_raptor.global_position
	host_raptor.set_physics_process(false)
	client_raptor.set_physics_process(false)
	var client_combat: NetCombat = client.get_node("NetCombat")
	client_combat.request_bow_aim(client_avatar, true, Vector2.RIGHT)
	if not await _rig.pump_until(func() -> bool:
		return host_avatar.bow_aiming and client_avatar.bow_aiming, 3.0):
		return _fail("원격 조준 자세 복제 실패")
	client_combat.request_bow_fire(client_avatar, Vector2.RIGHT)
	if not await _rig.pump_until(func() -> bool:
		return host_raptor.current_health < host_raptor.data.max_health, 5.0):
		return _fail("호스트 활 피해 미관측")
	if not await _rig.pump_until(func() -> bool:
		return host.get_node_or_null("RecoveredArrow1") != null \
			and client.get_node_or_null("RecoveredArrow1") != null, 3.0):
		return _fail("회수 화살 드롭 복제 실패")
	var host_arrow: WorldItem = host.get_node("RecoveredArrow1")
	var client_arrow: WorldItem = client.get_node("RecoveredArrow1")
	host_avatar.global_position = host_arrow.global_position
	client_avatar.global_position = client_arrow.global_position
	client_arrow.interact(client_avatar)
	if not await _rig.pump_until(func() -> bool:
		return host_avatar.inventory.count_of(&"arrow") == 1 \
			and client_avatar.inventory.count_of(&"arrow") == 1 \
			and host.get_node_or_null("RecoveredArrow1") == null \
			and client.get_node_or_null("RecoveredArrow1") == null, 3.0):
		return _fail("회수 화살 획득 복제 실패")
	host_avatar.inventory.add_item(&"stone_spear", 1)
	if not client_equipment.request_equip(client_avatar, &"stone_spear"):
		return _fail("클라이언트 창 장착 의도 전송 실패")
	if not await _rig.pump_until(func() -> bool:
		return host_avatar.equipment.get_equipped(&"main_hand") == &"stone_spear" \
			and client_avatar.equipment.get_equipped(&"main_hand") == &"stone_spear", 5.0):
		return _fail("창 장착 복제 실패")
	host_raptor.global_position = host_avatar.global_position + Vector2(90, 0)
	client_raptor.global_position = client_avatar.global_position + Vector2(90, 0)
	await create_timer(NetCombat.BOW_RELOAD_SECONDS + 0.1).timeout
	client_combat.request_attack(client_avatar, Vector2.RIGHT)
	await create_timer(NetCombat.ATTACK_COOLDOWN + 0.15).timeout
	client_combat.request_attack(client_avatar, Vector2.RIGHT)
	if not await _rig.pump_until(func() -> bool:
		return host.get_node_or_null("RaptorCarcass") != null \
			and client.get_node_or_null("RaptorCarcass") != null, 5.0):
		return _fail("사망 후 사체 복제 실패")
	print("[two-player-combat] PASS client bow aim/fire → host damage → arrow recovered → spear death")
	_rig.disconnect_all()
	quit(0)

func _make_machine(machine_name: String) -> Node:
	var root := Node.new()
	root.name = machine_name
	get_root().add_child(root)
	set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var main: Node2D = MainScene.instantiate()
	main.name = "Main"
	root.add_child(main)
	return root

func _fail(reason: String) -> void:
	print("[two-player-combat] FAIL: %s" % reason)
	_rig.disconnect_all()
	quit(1)

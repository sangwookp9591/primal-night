extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const RECONNECT_ID: StringName = &"76561198000000999"

var rig: NetTestRig
var host: Dictionary
var client: Dictionary


func before_each() -> void:
	rig = NetTestRig.new(get_tree())
	host = _make_side("EquipmentHost")
	client = _make_side("EquipmentClient")


func after_each() -> void:
	rig.disconnect_all()
	get_tree().set_multiplayer(null, host.root.get_path())
	get_tree().set_multiplayer(null, client.root.get_path())


func _make_side(side_name: String) -> Dictionary:
	var root: Node = add_child_autofree(Node.new())
	root.name = side_name
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())

	var session := LocalSessionService.new()
	session.name = "NetSession"
	session.config = NetConfig.new()
	root.add_child(session)

	var host_player: Player = PlayerScene.instantiate()
	host_player.name = "Player"
	root.add_child(host_player)

	var players := Node2D.new()
	players.name = "Players"
	root.add_child(players)

	var movement := NetMovement.new()
	movement.name = "NetMovement"
	movement.avatar_scene = PlayerScene
	movement.config = session.config
	root.add_child(movement)

	var equipment := NetEquipment.new()
	equipment.name = "NetEquipment"
	root.add_child(equipment)
	return {
		root = root,
		session = session,
		host_player = host_player,
		players = players,
		movement = movement,
		equipment = equipment,
	}


func _join(player_id: StringName = &"") -> StringName:
	assert_eq(rig.start_host(host.session), OK)
	assert_eq(rig.connect_client(client.session, host.session, player_id), OK)
	assert_true(await rig.pump_until(func() -> bool:
		var id: StringName = client.session.get_local_player_id()
		return host.players.has_node(NodePath(String(id))) \
			and client.players.has_node(NodePath(String(id))), 5.0))
	return client.session.get_local_player_id()


func _host_avatar(player_id: StringName) -> Player:
	return host.players.get_node_or_null(NodePath(String(player_id))) as Player


func _client_avatar(player_id: StringName) -> Player:
	return client.players.get_node_or_null(NodePath(String(player_id))) as Player


func test_client_unequip_and_equip_round_trip_is_host_authoritative() -> void:
	var player_id := await _join()
	var host_avatar := _host_avatar(player_id)
	var client_avatar := _client_avatar(player_id)

	assert_true(client.equipment.request_unequip(client_avatar, &"outfit"))
	# 요청 직후에는 클라이언트가 직접 확정하면 안 된다.
	assert_eq(client_avatar.equipment.get_equipped(&"outfit"), &"white_underwear")
	assert_true(await rig.pump_until(func() -> bool:
		return host_avatar.equipment.get_equipped(&"outfit") == &"" \
			and client_avatar.equipment.get_equipped(&"outfit") == &"" \
			and client_avatar.inventory.count_of(&"white_underwear") == 1, 3.0))
	assert_eq(host_avatar.inventory.count_of(&"white_underwear"), 1)

	assert_true(client.equipment.request_equip(client_avatar, &"white_underwear"))
	assert_true(await rig.pump_until(func() -> bool:
		return host_avatar.equipment.get_equipped(&"outfit") == &"white_underwear" \
			and client_avatar.equipment.get_equipped(&"outfit") == &"white_underwear" \
			and client_avatar.inventory.count_of(&"white_underwear") == 0, 3.0))
	assert_eq(host_avatar.inventory.count_of(&"white_underwear"), 0)


func test_client_equipment_replacement_replicates_inventory_atomically() -> void:
	var player_id := await _join()
	var host_avatar := _host_avatar(player_id)
	var client_avatar := _client_avatar(player_id)
	assert_eq(host_avatar.inventory.add_item(&"bow", 1), 1)
	assert_eq(client_avatar.inventory.add_item(&"bow", 1), 1)
	assert_eq(host_avatar.inventory.add_item(&"stone_spear", 1), 1)
	assert_eq(client_avatar.inventory.add_item(&"stone_spear", 1), 1)

	assert_true(client.equipment.request_equip(client_avatar, &"bow"))
	assert_true(await rig.pump_until(func() -> bool:
		return client_avatar.equipment.get_equipped(&"main_hand") == &"bow" \
			and client_avatar.inventory.count_of(&"bow") == 0, 3.0))
	assert_true(client.equipment.request_equip(client_avatar, &"stone_spear"))
	assert_true(await rig.pump_until(func() -> bool:
		return client_avatar.equipment.get_equipped(&"main_hand") == &"stone_spear" \
			and client_avatar.inventory.count_of(&"stone_spear") == 0 \
			and client_avatar.inventory.count_of(&"bow") == 1, 3.0))
	assert_eq(client_avatar.inventory.count_of(&"bow"),
		host_avatar.inventory.count_of(&"bow"))
	assert_eq(client_avatar.inventory.count_of(&"stone_spear"),
		host_avatar.inventory.count_of(&"stone_spear"))


func test_late_join_receives_existing_host_snapshot() -> void:
	assert_eq(rig.start_host(host.session), OK)
	assert_true(host.equipment.request_unequip(host.host_player, &"outfit"))
	assert_eq(host.host_player.equipment.get_equipped(&"outfit"), &"")
	assert_eq(host.host_player.inventory.count_of(&"white_underwear"), 1)

	assert_eq(rig.connect_client(client.session, host.session), OK)
	assert_true(await rig.pump_until(func() -> bool:
		return client.host_player.equipment.get_equipped(&"outfit") == &"" \
			and client.host_player.inventory.count_of(&"white_underwear") == 1, 5.0),
		"늦은 참가자는 기존 호스트 장비와 권위 인벤토리 스냅샷을 받아야 한다")


func test_reconnect_restores_equipment_and_remote_visual() -> void:
	var player_id := await _join(RECONNECT_ID)
	var host_avatar := _host_avatar(player_id)
	var client_avatar := _client_avatar(player_id)
	assert_true(client.equipment.request_unequip(client_avatar, &"outfit"))
	assert_true(await rig.pump_until(func() -> bool:
		return host_avatar.equipment.get_equipped(&"outfit") == &"", 3.0))

	client.session.leave_session()
	assert_true(await rig.pump_until(func() -> bool:
		return host.session.has_reconnect_slot(player_id), 3.0))
	assert_eq(rig.connect_client(client.session, host.session, player_id), OK)
	assert_true(await rig.pump_until(func() -> bool:
		var restored := _client_avatar(player_id)
		return restored != null and restored.equipment.get_equipped(&"outfit") == &"", 5.0))
	var restored_client := _client_avatar(player_id)
	assert_false(restored_client.visual_rig.outfit.visible)
	assert_eq(_host_avatar(player_id).equipment.get_snapshot(),
		restored_client.equipment.get_snapshot())
	assert_eq(_host_avatar(player_id).inventory.count_of(&"white_underwear"),
		restored_client.inventory.count_of(&"white_underwear"))


func test_tampered_other_avatar_and_unknown_item_are_rejected() -> void:
	var player_id := await _join()
	var sender_peer: int = client.root.multiplayer.get_unique_id()
	var before := _host_avatar(player_id).equipment.get_snapshot()
	client.equipment.submit_equipment_intent.rpc_id(
		RpcGuard.HOST_PEER_ID, String(host.session.get_local_player_id()),
		NetEquipment.ACTION_UNEQUIP, "outfit")
	client.equipment.submit_equipment_intent.rpc_id(
		RpcGuard.HOST_PEER_ID, String(player_id),
		NetEquipment.ACTION_EQUIP, "definitely_unknown_item")
	assert_true(await rig.pump_until(func() -> bool:
		return host.equipment.get_rejection_count() >= 2, 3.0))
	assert_push_error("Missing item data")
	assert_eq(_host_avatar(player_id).equipment.get_snapshot(), before)
	assert_eq(host.equipment.get_guard_violation_count(sender_peer), 0,
		"스키마 내 도메인 변조는 RpcGuard 통과 후 NetEquipment가 진단한다")


func test_disconnect_at_request_boundary_never_loses_or_duplicates_item() -> void:
	var player_id := await _join()
	var host_avatar := _host_avatar(player_id)
	var client_avatar := _client_avatar(player_id)
	assert_true(client.equipment.request_unequip(client_avatar, &"outfit"))
	client.session.leave_session()
	assert_true(await rig.pump_until(func() -> bool:
		return host.session.has_reconnect_slot(player_id), 3.0))
	# reliable 요청이 이탈보다 먼저 확정되거나 이탈로 폐기되는 두 결과 모두 안전하다.
	var equipped_count: int = 0 if host_avatar.equipment.get_equipped(&"outfit") == &"" else 1
	assert_eq(equipped_count + host_avatar.inventory.count_of(&"white_underwear"), 1,
		"연결 종료 경계에서도 장비 아이템 총량은 정확히 하나여야 한다")


func test_remote_snapshot_and_visual_match_host_confirmation() -> void:
	var player_id := await _join()
	var host_avatar := _host_avatar(player_id)
	var client_avatar := _client_avatar(player_id)
	assert_true(client.equipment.request_unequip(client_avatar, &"outfit"))
	assert_true(await rig.pump_until(func() -> bool:
		return host_avatar.equipment.get_equipped(&"outfit") == &"" \
			and client_avatar.equipment.get_equipped(&"outfit") == &"" \
			and client_avatar.equipment.get_snapshot() == host_avatar.equipment.get_snapshot(), 3.0))
	assert_false(client_avatar.visual_rig.outfit.visible)
	assert_false(host_avatar.visual_rig.outfit.visible)

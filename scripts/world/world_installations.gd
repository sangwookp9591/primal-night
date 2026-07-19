class_name WorldInstallations
extends Node

const SNARE_SCENE: PackedScene = preload("res://scenes/world/snare_trap.tscn")
const SHELTER_SCENE: PackedScene = preload("res://scenes/world/field_shelter.tscn")

@export var host_player_path: NodePath = ^"../Player"
@export var session_path: NodePath = ^"../NetSession"
@export var players_container_path: NodePath = ^"../Players"
var _serial: int = 0
var _session: SessionService
var _players: Node


func _ready() -> void:
	add_to_group(&"world_installations")
	_session = get_node_or_null(session_path) as SessionService
	_players = get_node_or_null(players_container_path)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_lure"):
		var player := get_node_or_null(host_player_path) as Player
		if player != null:
			if player.inventory.has_item(&"shelter_kit", 1):
				request_place(player, &"shelter_kit")
			elif player.inventory.has_item(&"snare_kit", 1):
				request_place(player, &"snare_kit")


func request_place(who: Player, kit_id: StringName) -> Node2D:
	if who == null or kit_id not in [&"snare_kit", &"shelter_kit"]:
		return null
	if not multiplayer.is_server():
		request_install.rpc_id(1, String(kit_id))
		return null
	return _host_place(who, kit_id)


func _host_place(who: Player, kit_id: StringName) -> Node2D:
	if not who.inventory.remove_item(kit_id, 1):
		return null
	var placed := (SHELTER_SCENE if kit_id == &"shelter_kit" else SNARE_SCENE).instantiate() as Node2D
	placed.name = "%s_%d" % [String(kit_id), _serial]
	_serial += 1
	get_parent().add_child(placed)
	placed.global_position = who.global_position + who.facing_direction() * 48.0
	if not multiplayer.get_peers().is_empty():
		confirm_install.rpc(String(kit_id), String(placed.name), placed.global_position,
			String(_player_id_of(who)))
	return placed


@rpc("any_peer", "call_remote", "reliable")
func request_install(kit_id_text: String) -> void:
	if not multiplayer.is_server():
		return
	var kit_id := StringName(kit_id_text)
	if kit_id not in [&"snare_kit", &"shelter_kit"] or _session == null:
		return
	var player_id := _session.get_player_id_for_peer(multiplayer.get_remote_sender_id())
	var who := _avatar_of(player_id)
	if who != null:
		_host_place(who, kit_id)


@rpc("authority", "call_remote", "reliable")
func confirm_install(kit_id_text: String, node_name: String,
		position_value: Vector2, player_id_text: String) -> void:
	var kit_id := StringName(kit_id_text)
	if kit_id not in [&"snare_kit", &"shelter_kit"] or not position_value.is_finite() \
			or node_name.is_empty() or node_name.length() > 64:
		return
	var placed := (SHELTER_SCENE if kit_id == &"shelter_kit" else SNARE_SCENE).instantiate() as Node2D
	placed.name = node_name
	get_parent().add_child(placed)
	placed.global_position = position_value
	var who := _avatar_of(StringName(player_id_text))
	if who != null:
		who.inventory.remove_item(kit_id, 1)


func _avatar_of(player_id: StringName) -> Player:
	var host := get_node_or_null(host_player_path) as Player
	if _session != null and player_id == _session.get_player_id_for_peer(1):
		return host
	return _players.get_node_or_null(NodePath(String(player_id))) as Player if _players != null else null


func _player_id_of(who: Player) -> StringName:
	var host := get_node_or_null(host_player_path) as Player
	if who == host and _session != null:
		return _session.get_player_id_for_peer(1)
	return StringName(who.name)


func request_shelter_use(who: Player, shelter: FieldShelter) -> void:
	if multiplayer.is_server():
		if shelter.use_authoritative(who) and not multiplayer.get_peers().is_empty():
			confirm_shelter_used.rpc(String(get_parent().get_path_to(shelter)))
		return
	request_shelter.rpc_id(1, String(get_parent().get_path_to(shelter)))


@rpc("any_peer", "call_remote", "reliable")
func request_shelter(path: String) -> void:
	if not multiplayer.is_server() or _session == null:
		return
	var shelter := get_parent().get_node_or_null(NodePath(path)) as FieldShelter
	var who := _avatar_of(_session.get_player_id_for_peer(multiplayer.get_remote_sender_id()))
	if shelter != null and shelter.use_authoritative(who):
		confirm_shelter_used.rpc(path)


@rpc("authority", "call_remote", "reliable")
func confirm_shelter_used(path: String) -> void:
	var shelter := get_parent().get_node_or_null(NodePath(path)) as FieldShelter
	if shelter != null:
		shelter.apply_state(true)


func request_snare_recover(who: Player, trap: SnareTrap) -> void:
	if multiplayer.is_server():
		if trap.recover_authoritative(who) and not multiplayer.get_peers().is_empty():
			confirm_snare_recovered.rpc(String(get_parent().get_path_to(trap)),
				String(_player_id_of(who)))
		return
	request_snare.rpc_id(1, String(get_parent().get_path_to(trap)))


@rpc("any_peer", "call_remote", "reliable")
func request_snare(path: String) -> void:
	if not multiplayer.is_server() or _session == null:
		return
	var trap := get_parent().get_node_or_null(NodePath(path)) as SnareTrap
	var who := _avatar_of(_session.get_player_id_for_peer(multiplayer.get_remote_sender_id()))
	if trap != null and trap.recover_authoritative(who):
		confirm_snare_recovered.rpc(path, String(_player_id_of(who)))


@rpc("authority", "call_remote", "reliable")
func confirm_snare_recovered(path: String, player_id: String) -> void:
	var trap := get_parent().get_node_or_null(NodePath(path)) as SnareTrap
	var who := _avatar_of(StringName(player_id))
	if trap != null and who != null:
		who.inventory.add_item(&"raw_meat", trap.raw_meat_yield)
		who.inventory.add_item(&"hide", trap.hide_yield)
		trap.queue_free()

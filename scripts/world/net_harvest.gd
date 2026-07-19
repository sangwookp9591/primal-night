class_name NetHarvest
extends Node

const MAX_DISTANCE: float = 128.0
const MAX_PATH: int = 160

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
@export var world_root_path: NodePath = ^".."

var _session: SessionService
var _host_player: Player
var _players: Node2D
var _world_root: Node


func _ready() -> void:
	add_to_group(&"net_harvest")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_players = get_node(players_container_path)
	_world_root = get_node(world_root_path)


func owns(node: Node) -> bool:
	return _world_root.is_ancestor_of(node)


func request_harvest(node: HarvestableNode, who: Player) -> void:
	if multiplayer.is_server():
		_host_harvest(who, node)
	else:
		request_harvest_rpc.rpc_id(1, String(_world_root.get_path_to(node)))


func request_pulse(node: HarvestableNode, who: Player) -> void:
	if multiplayer.is_server():
		_host_pulse(who, node)
	else:
		request_pulse_rpc.rpc_id(1, String(_world_root.get_path_to(node)))


func request_water(source: WaterSource, who: Player) -> void:
	if multiplayer.is_server():
		_host_water(who, source)
	else:
		request_water_rpc.rpc_id(1, String(_world_root.get_path_to(source)))


@rpc("any_peer", "call_remote", "reliable")
func request_harvest_rpc(path: String) -> void:
	if multiplayer.is_server() and RpcGuard.is_safe_relative_path(path, MAX_PATH):
		_host_harvest(_sender_avatar(), _world_root.get_node_or_null(path) as HarvestableNode)


@rpc("any_peer", "call_remote", "unreliable")
func request_pulse_rpc(path: String) -> void:
	if multiplayer.is_server() and RpcGuard.is_safe_relative_path(path, MAX_PATH):
		_host_pulse(_sender_avatar(), _world_root.get_node_or_null(path) as HarvestableNode)


@rpc("any_peer", "call_remote", "reliable")
func request_water_rpc(path: String) -> void:
	if multiplayer.is_server() and RpcGuard.is_safe_relative_path(path, MAX_PATH):
		_host_water(_sender_avatar(), _world_root.get_node_or_null(path) as WaterSource)


func _host_harvest(who: Player, node: HarvestableNode) -> void:
	if not _valid(who, node):
		return
	if not node.apply_harvest(who):
		return
	if multiplayer.get_peers().size() > 0:
		confirm_harvest.rpc(String(_world_root.get_path_to(node)), String(_player_id(who)),
			String(node.reward_id), node.reward_count)


func _host_pulse(who: Player, node: HarvestableNode) -> void:
	if _valid(who, node):
		node.emit_harvest_noise(who)


func _host_water(who: Player, source: WaterSource) -> void:
	if who == null or source == null \
			or who.global_position.distance_to(source.global_position) > MAX_DISTANCE:
		return
	var action := source.apply_water_action(who)
	if not action.is_empty() and multiplayer.get_peers().size() > 0:
		confirm_water.rpc(String(_world_root.get_path_to(source)),
			String(_player_id(who)), String(action))


@rpc("authority", "call_remote", "reliable")
func confirm_harvest(path: String, player_id: String, reward_id: String, count: int) -> void:
	if not RpcGuard.is_safe_relative_path(path, MAX_PATH) or count <= 0:
		return
	var node := _world_root.get_node_or_null(path) as HarvestableNode
	if node != null:
		node.receive_depleted()
	var avatar := _avatar(StringName(player_id))
	if avatar != null:
		avatar.inventory.add_item(StringName(reward_id), count)


@rpc("authority", "call_remote", "reliable")
func confirm_water(path: String, player_id: String, action: String) -> void:
	if not RpcGuard.is_safe_relative_path(path, MAX_PATH) \
			or action not in ["fill", "drink"]:
		return
	var source := _world_root.get_node_or_null(path) as WaterSource
	var avatar := _avatar(StringName(player_id))
	if source != null and avatar != null:
		source.apply_water_action(avatar, StringName(action))


func _valid(who: Player, node: HarvestableNode) -> bool:
	return who != null and node != null and node.available \
		and who.global_position.distance_to(node.global_position) <= MAX_DISTANCE


func _sender_avatar() -> Player:
	return _avatar(_session.get_player_id_for_peer(multiplayer.get_remote_sender_id()))


func _avatar(id: StringName) -> Player:
	if id == _session.get_player_id_for_peer(1):
		return _host_player
	return _players.get_node_or_null(NodePath(String(id))) as Player


func _player_id(who: Player) -> StringName:
	return _session.get_player_id_for_peer(1) if who == _host_player else StringName(who.name)

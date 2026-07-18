class_name NetBaseCamp
extends Node

const MAX_DISTANCE_PX: float = 160.0
const PATH_MAX_LENGTH: int = 128

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
@export var world_root_path: NodePath = ^".."

var _session: SessionService
var _host_player: Player
var _players: Node
var _world_root: Node

func _ready() -> void:
	add_to_group(&"net_base_camp")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_players = get_node(players_container_path)
	_world_root = get_node(world_root_path)

func request_storage_transfer(cache: StorageCache, who: Player, item_id: StringName,
		to_storage: bool) -> void:
	if multiplayer.is_server():
		_host_storage_transfer(cache, who, item_id, to_storage)
	else:
		request_storage.rpc_id(RpcGuard.HOST_PEER_ID,
			String(_world_root.get_path_to(cache)), String(item_id), to_storage)

@rpc("any_peer", "call_remote", "reliable")
func request_storage(cache_path: String, item_id: String, to_storage: bool) -> void:
	if not multiplayer.is_server() or not RpcGuard.is_safe_relative_path(cache_path, PATH_MAX_LENGTH):
		return
	var who := _avatar_of(_session.get_player_id_for_peer(multiplayer.get_remote_sender_id()))
	var cache := _world_root.get_node_or_null(cache_path) as StorageCache
	_host_storage_transfer(cache, who, StringName(item_id), to_storage)

func _host_storage_transfer(cache: StorageCache, who: Player, item_id: StringName,
		to_storage: bool) -> bool:
	if cache == null or who == null or item_id == &"" \
			or who.global_position.distance_to(cache.global_position) > MAX_DISTANCE_PX:
		return false
	var source: Inventory = who.inventory if to_storage else cache.inventory
	var destination: Inventory = cache.inventory if to_storage else who.inventory
	if not source.has_item(item_id, 1):
		return false
	var source_before := source.get_transaction_snapshot()
	var destination_before := destination.get_transaction_snapshot()
	if not source.remove_item(item_id, 1) or destination.add_item(item_id, 1) != 1:
		source.restore_transaction_snapshot(source_before)
		destination.restore_transaction_snapshot(destination_before)
		return false
	if multiplayer.get_peers().size() > 0:
		confirm_storage.rpc(String(_world_root.get_path_to(cache)), String(_player_id_of(who)),
			String(item_id), to_storage)
	return true

@rpc("authority", "call_remote", "reliable")
func confirm_storage(cache_path: String, player_id: String, item_id: String,
		to_storage: bool) -> void:
	var cache := _world_root.get_node_or_null(cache_path) as StorageCache
	var who := _avatar_of(StringName(player_id))
	if cache == null or who == null:
		return
	var source: Inventory = who.inventory if to_storage else cache.inventory
	var destination: Inventory = cache.inventory if to_storage else who.inventory
	if source.remove_item(StringName(item_id), 1):
		destination.add_item(StringName(item_id), 1)

func request_drying_interaction(rack: DryingRack, who: Player) -> void:
	if multiplayer.is_server():
		_host_drying(rack, who)
	else:
		request_drying.rpc_id(RpcGuard.HOST_PEER_ID, String(_world_root.get_path_to(rack)))

@rpc("any_peer", "call_remote", "reliable")
func request_drying(rack_path: String) -> void:
	if not multiplayer.is_server() or not RpcGuard.is_safe_relative_path(rack_path, PATH_MAX_LENGTH):
		return
	_host_drying(_world_root.get_node_or_null(rack_path) as DryingRack,
		_avatar_of(_session.get_player_id_for_peer(multiplayer.get_remote_sender_id())))

func _host_drying(rack: DryingRack, who: Player) -> bool:
	if rack == null or who == null \
			or who.global_position.distance_to(rack.global_position) > MAX_DISTANCE_PX:
		return false
	if rack.item_id == &"":
		if not who.inventory.remove_item(DryingRack.RAW_MEAT, 1):
			return false
		rack.apply_state(DryingRack.RAW_MEAT, 0.0)
	elif rack.item_id == DryingRack.DRIED_MEAT:
		if who.inventory.add_item(DryingRack.DRIED_MEAT, 1) != 1:
			return false
		rack.apply_state(&"", 0.0)
	else:
		return false
	replicate_drying_state(rack)
	return true

func replicate_drying_state(rack: DryingRack) -> void:
	if multiplayer.get_peers().size() > 0:
		confirm_drying.rpc(String(_world_root.get_path_to(rack)),
			String(rack.item_id), rack.elapsed_seconds)

@rpc("authority", "call_remote", "reliable")
func confirm_drying(rack_path: String, item_id: String, elapsed: float) -> void:
	var rack := _world_root.get_node_or_null(rack_path) as DryingRack
	if rack != null:
		rack.apply_state(StringName(item_id), elapsed)

func request_bedding(bedding: Bedding, who: Player, active: bool, multiplier: float) -> void:
	if multiplayer.is_server():
		_host_bedding(bedding, who, active, multiplier)
	else:
		request_rest.rpc_id(RpcGuard.HOST_PEER_ID,
			String(_world_root.get_path_to(bedding)), active)

@rpc("any_peer", "call_remote", "reliable")
func request_rest(bedding_path: String, active: bool) -> void:
	if not multiplayer.is_server() \
			or not RpcGuard.is_safe_relative_path(bedding_path, PATH_MAX_LENGTH):
		return
	_host_bedding(_world_root.get_node_or_null(bedding_path) as Bedding,
		_avatar_of(_session.get_player_id_for_peer(multiplayer.get_remote_sender_id())), active, 8.0)

func _host_bedding(bedding: Bedding, who: Player, active: bool, multiplier: float) -> void:
	if bedding != null and who != null and who.stats != null \
			and who.global_position.distance_to(bedding.global_position) <= MAX_DISTANCE_PX:
		who.stats.set_rest_multiplier(multiplier if active else 1.0)

func _avatar_of(player_id: StringName) -> Player:
	if player_id == _session.local_player_id:
		return _host_player
	return _players.get_node_or_null(String(player_id)) as Player

func _player_id_of(who: Player) -> StringName:
	if who == _host_player:
		return _session.local_player_id
	return StringName(who.name)

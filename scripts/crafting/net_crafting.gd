class_name NetCrafting
extends Node

## 퀵 제작 호스트 권위. 클라이언트는 recipe_id 의도만 보내고,
## 재료·결과·수량은 호스트 GameData 의 RecipeData 로만 판정한다.

const RECIPE_ID_MAX_LENGTH: int = 48
const PLAYER_ID_MAX_LENGTH: int = 32
const REQUEST_MAX_PER_SECOND: int = 6
const CONFIRM_MAX_PER_SECOND: int = 12

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _guard: RpcGuard
var _game_data: Node
var _crafting: Crafting = Crafting.new()
var _now_seconds: float = 0.0


func _ready() -> void:
	add_to_group(&"net_crafting")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_game_data = get_node("/root/GameData")
	add_child(_crafting)
	_guard = RpcGuard.new()
	_guard.register_rule(&"request_quick_craft", false, REQUEST_MAX_PER_SECOND, RECIPE_ID_MAX_LENGTH)
	_guard.register_rule(&"confirm_quick_craft", true, CONFIRM_MAX_PER_SECOND,
		RECIPE_ID_MAX_LENGTH + PLAYER_ID_MAX_LENGTH)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_guard.watch_session(_session)


func _physics_process(delta: float) -> void:
	_now_seconds += delta


func request(recipe_id: StringName, who: Player) -> void:
	if multiplayer.is_server():
		_host_craft(who, recipe_id)
		return
	request_quick_craft.rpc_id(RpcGuard.HOST_PEER_ID, String(recipe_id))


@rpc("any_peer", "call_remote", "reliable")
func request_quick_craft(recipe_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_quick_craft", sender, recipe_id.length(), _now_seconds):
		return
	if recipe_id.is_empty() or recipe_id.length() > RECIPE_ID_MAX_LENGTH:
		push_warning("NetCrafting: request_quick_craft 스키마 위반 — 폐기 sender=%d" % sender)
		return
	_host_craft(_avatar_of(_session.get_player_id_for_peer(sender)), StringName(recipe_id))


func _host_craft(who: Player, recipe_id: StringName) -> void:
	if who == null or not is_instance_valid(who):
		return
	var recipe: RecipeData = _game_data.get_recipe(recipe_id)
	if not _crafting.craft(who, recipe):
		return
	if multiplayer.get_peers().size() > 0:
		confirm_quick_craft.rpc(String(recipe_id), String(_player_id_of(who)))


@rpc("authority", "call_remote", "reliable")
func confirm_quick_craft(recipe_id: String, player_id: String) -> void:
	if not _guard.check(&"confirm_quick_craft", multiplayer.get_remote_sender_id(),
			recipe_id.length() + player_id.length(), _now_seconds):
		return
	if recipe_id.is_empty() or recipe_id.length() > RECIPE_ID_MAX_LENGTH \
			or player_id.is_empty() or player_id.length() > PLAYER_ID_MAX_LENGTH:
		push_warning("NetCrafting: confirm_quick_craft 스키마 위반 — 폐기")
		return
	_crafting.craft(_avatar_of(StringName(player_id)), _game_data.get_recipe(StringName(recipe_id)))


func _host_id() -> StringName:
	return _session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID)


func _avatar_of(player_id: StringName) -> Player:
	if player_id == _host_id():
		return _host_player
	return _container.get_node_or_null(NodePath(String(player_id))) as Player


func _player_id_of(who: Player) -> StringName:
	if who == _host_player:
		return _host_id()
	return StringName(who.name)

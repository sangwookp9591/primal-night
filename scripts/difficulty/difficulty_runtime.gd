class_name DifficultyRuntime
extends Node

const PRESETS := {
	&"gentle": preload("res://resources/difficulty/gentle.tres"),
	&"standard": preload("res://resources/difficulty/standard.tres"),
	&"harsh": preload("res://resources/difficulty/harsh.tres"),
}

static var pending_preset_id: StringName = &"standard"
static var has_pending_selection: bool = false
static var current_config: DifficultyConfig = PRESETS[&"standard"]

var config: DifficultyConfig = PRESETS[&"standard"]
var _penalized_players: Dictionary = {}

static func preset(id: StringName) -> DifficultyConfig:
	return PRESETS.get(id, PRESETS[&"standard"])

static func select_for_next_game(id: StringName) -> void:
	pending_preset_id = preset(id).id
	has_pending_selection = true

func _ready() -> void:
	var selected := pending_preset_id if has_pending_selection else &"standard"
	has_pending_selection = false
	pending_preset_id = &"standard"
	apply_preset(selected)
	var session := get_parent().get_node_or_null("NetSession") as LocalSessionService
	if session != null:
		session.player_joined.connect(_on_player_joined)
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.damage_taken.connect(_on_damage_taken)

func apply_preset(id: StringName) -> void:
	config = preset(id)
	current_config = config
	for item: WorldItem in get_tree().get_nodes_in_group(&"world_item"):
		if get_parent().is_ancestor_of(item):
			item.apply_spawn_quantity_multiplier(config.resource_spawn_quantity_multiplier)
	for raptor: Raptor in get_tree().get_nodes_in_group(&"raptor"):
		if get_parent().is_ancestor_of(raptor):
			raptor.apply_difficulty(config)

func _on_player_joined(_player_id: StringName) -> void:
	if multiplayer.is_server():
		receive_host_difficulty.rpc(config.id)

@rpc("authority", "call_remote", "reliable")
func receive_host_difficulty(id: StringName) -> void:
	apply_preset(id)

func _on_damage_taken(target: Node, _amount: float, _kind: StringName) -> void:
	var player := target as Player
	if player == null or not get_parent().is_ancestor_of(player) \
		or player.health.is_alive() or _penalized_players.has(player):
		return
	_penalized_players[player] = true
	player.inventory.apply_death_keep_ratio(config.death_item_keep_ratio, player.get_parent())

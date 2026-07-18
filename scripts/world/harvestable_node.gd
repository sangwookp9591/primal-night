class_name HarvestableNode
extends Area2D

const VEGETATION_SHEET: Texture2D = preload(
	"res://assets/sprites/props/valley_vegetation_8_sheet.png")
const HARVEST_NOISE: NoiseProfile = preload("res://data/senses/noise_harvest.tres")
const CELL_SIZE := Vector2(128.0, 128.0)
const HIT_INTERVAL: float = 0.5

@export_enum("tree", "berry_bush") var harvest_kind: String = "tree"
@export var reward_id: StringName = &"wood"
@export_range(1, 2, 1) var reward_count: int = 2
@export var hold_seconds: float = 2.75
@export var respawn_seconds: float = 180.0
@export_range(0, 7, 1) var vegetation_index: int = 0

var available: bool = true
var _respawn_remaining: float = 0.0
var _hit_remaining: float = 0.0
var _holder: Player = null
var _event_bus: Node = null
var _noise_emitter := NoiseEmitter.new()


func _ready() -> void:
	add_to_group(&"harvestable")
	_event_bus = get_node_or_null("/root/EventBus")
	_configure_visual()
	_configure_respawn_from_difficulty.call_deferred()
	set_process(false)


func _configure_respawn_from_difficulty() -> void:
	respawn_seconds *= DifficultyRuntime.current_config.resource_respawn_time_multiplier


func _configure_visual() -> void:
	var plant := $Plant as Sprite2D
	var atlas := AtlasTexture.new()
	atlas.atlas = VEGETATION_SHEET
	atlas.region = Rect2(Vector2(vegetation_index % 4, vegetation_index / 4) * CELL_SIZE, CELL_SIZE)
	plant.texture = atlas
	plant.offset = Vector2(0.0, -64.0)
	plant.scale = Vector2(0.72, 0.72) if harvest_kind == "tree" else Vector2(0.58, 0.58)
	$BerryOverlay.visible = harvest_kind == "berry_bush"
	if harvest_kind == "berry_bush":
		$BerryOverlay.texture = WorldItem.icon_texture(&"berry")


func can_interact(who: Node) -> bool:
	return available and who is Player


func get_hold_seconds() -> float:
	return hold_seconds


func get_prompt() -> String:
	return "나무 베기" if harvest_kind == "tree" else "열매 따기"


func on_hold_started(who: Node) -> void:
	_holder = who as Player
	_hit_remaining = 0.0
	set_process(true)


func on_hold_ended(_who: Node) -> void:
	_holder = null
	set_process(multiplayer.is_server() and not available)


func _process(delta: float) -> void:
	if not available:
		if not multiplayer.is_server():
			set_process(false)
			return
		_respawn_remaining = maxf(_respawn_remaining - delta, 0.0)
		if _respawn_remaining <= 0.0:
			_restore()
		return
	if _holder == null:
		set_process(false)
		return
	_hit_remaining -= delta
	if _hit_remaining > 0.0:
		return
	_hit_remaining = HIT_INTERVAL
	play_shake()
	_holder.play_harvest_feedback(global_position, 0.55 if harvest_kind == "berry_bush" else 1.0)
	var net := _find_net_harvest()
	if net != null:
		net.request_pulse(self, _holder)
	else:
		emit_harvest_noise(_holder)


func interact(who: Node) -> void:
	var player := who as Player
	if player == null or not available:
		return
	var net := _find_net_harvest()
	if net != null:
		net.request_harvest(self, player)
	else:
		apply_harvest(player)


func apply_harvest(player: Player) -> bool:
	if not available or player == null:
		return false
	var granted := player.inventory.add_item(reward_id, reward_count)
	if granted != reward_count:
		if granted > 0:
			player.inventory.remove_item(reward_id, granted)
		return false
	_deplete()
	return true


func emit_harvest_noise(source: Node) -> void:
	_noise_emitter.emit_profile(_event_bus, HARVEST_NOISE, global_position, source)


func play_shake() -> void:
	var plant := $Plant as Sprite2D
	plant.rotation = 0.0
	var tween := create_tween()
	tween.tween_property(plant, "rotation", -0.045, 0.06)
	tween.tween_property(plant, "rotation", 0.04, 0.08)
	tween.tween_property(plant, "rotation", 0.0, 0.08)


func _deplete() -> void:
	available = false
	_respawn_remaining = respawn_seconds
	$BerryOverlay.visible = false
	$Plant.modulate.a = 0.38
	monitorable = false
	set_process(multiplayer.is_server())


func _restore() -> void:
	available = true
	$Plant.modulate.a = 1.0
	$BerryOverlay.visible = harvest_kind == "berry_bush"
	monitorable = true
	set_process(false)
	if multiplayer.get_peers().size() > 0:
		receive_restored.rpc()


@rpc("authority", "call_remote", "reliable")
func receive_depleted() -> void:
	if multiplayer.is_server():
		return
	_deplete()


@rpc("authority", "call_remote", "reliable")
func receive_restored() -> void:
	if multiplayer.is_server():
		return
	_restore()


func respawn_remaining_seconds() -> float:
	return _respawn_remaining


func _find_net_harvest() -> NetHarvest:
	for node: Node in get_tree().get_nodes_in_group(&"net_harvest"):
		if (node as NetHarvest).owns(self):
			return node as NetHarvest
	return null

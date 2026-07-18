class_name DryingRack
extends Area2D

const RAW_MEAT: StringName = &"raw_meat"
const DRIED_MEAT: StringName = &"dried_meat"

@export var drying_seconds: float = 90.0
@export var raw_smell_strength: float = 45.0
@export var dried_smell_strength: float = 10.0

var item_id: StringName = &""
var elapsed_seconds: float = 0.0
var _smell: SmellSource = null

func _ready() -> void:
	_refresh_smell()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or item_id != RAW_MEAT:
		return
	elapsed_seconds += delta
	if elapsed_seconds >= drying_seconds:
		item_id = DRIED_MEAT
		elapsed_seconds = drying_seconds
		_refresh_smell()
		var net := _net()
		if net != null:
			net.replicate_drying_state(self)

func can_interact(who: Node) -> bool:
	var player := who as Player
	return player != null and (item_id != &"" or player.inventory.has_item(RAW_MEAT, 1))

func get_hold_seconds() -> float:
	return 0.5

func get_prompt() -> String:
	if item_id == RAW_MEAT:
		return "고기 건조 중 (%d%%)" % floori(elapsed_seconds / drying_seconds * 100.0)
	if item_id == DRIED_MEAT:
		return "말린 고기 꺼내기"
	return "날고기 걸기"

func interact(who: Node) -> void:
	var player := who as Player
	var net := _net()
	if player != null and net != null:
		net.request_drying_interaction(self, player)

func apply_state(new_item_id: StringName, new_elapsed: float) -> void:
	item_id = new_item_id
	elapsed_seconds = clampf(new_elapsed, 0.0, drying_seconds)
	_refresh_smell()

func _refresh_smell() -> void:
	if item_id == &"":
		if _smell != null:
			_smell.deactivate()
			_smell.queue_free()
			_smell = null
		return
	if _smell == null:
		_smell = SmellSource.new()
		_smell.name = "HungMeatSmell"
		add_child(_smell)
	else:
		_smell.deactivate()
	_smell.kind = item_id
	_smell.strength = raw_smell_strength if item_id == RAW_MEAT else dried_smell_strength
	_smell.reactivate()

func current_smell_strength() -> float:
	return _smell.strength if _smell != null else 0.0

func _net() -> NetBaseCamp:
	var root: Node = get_parent()
	while root != null and root.get_node_or_null("NetBaseCamp") == null:
		root = root.get_parent()
	return root.get_node_or_null("NetBaseCamp") as NetBaseCamp if root != null else null

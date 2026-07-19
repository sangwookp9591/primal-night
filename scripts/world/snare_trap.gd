class_name SnareTrap
extends Area2D

enum State { ARMED, CAUGHT, SPOILED }

const BASE_SMELL: float = 8.0
const SPOILED_SMELL: float = 42.0
const SPOIL_SECONDS: float = 180.0

@export_range(0.0, 1.0) var capture_chance: float = 0.65
var state: int = State.ARMED
var unattended_seconds: float = 0.0
var raw_meat_yield: int = 0
var hide_yield: int = 0
var _grid: SmellGrid


func _ready() -> void:
	add_to_group(&"installation")
	add_to_group(&"snare_trap")
	_refresh_smell.call_deferred()


func _process(delta: float) -> void:
	if not multiplayer.is_server() or state == State.ARMED:
		return
	unattended_seconds += delta
	if state == State.CAUGHT and unattended_seconds >= SPOIL_SECONDS:
		state = State.SPOILED
		_refresh_smell()


func attempt_capture(scavenger: Scavenger, roll: float) -> bool:
	if not multiplayer.is_server() or state != State.ARMED or scavenger == null \
			or global_position.distance_to(scavenger.global_position) > Scavenger.FOOD_REACH_RADIUS:
		return false
	if clampf(roll, 0.0, 1.0) > capture_chance:
		return false
	state = State.CAUGHT
	raw_meat_yield = 2
	hide_yield = 1
	unattended_seconds = 0.0
	scavenger.queue_free()
	_refresh_smell()
	return true


func can_interact(who: Node) -> bool:
	return who is Player and state != State.ARMED


func get_hold_seconds() -> float:
	return 0.0


func get_prompt() -> String:
	return "올가미 회수"


func interact(who: Node) -> void:
	var player := who as Player
	if player == null or not can_interact(player):
		return
	if not multiplayer.is_server():
		var manager := get_tree().get_first_node_in_group(&"world_installations") as WorldInstallations
		if manager != null:
			manager.request_snare_recover(player, self)
		return
	recover_authoritative(player)


func recover_authoritative(player: Player) -> bool:
	if player == null or not multiplayer.is_server() or state == State.ARMED \
			or player.global_position.distance_to(global_position) > 96.0:
		return false
	var before := player.inventory.get_transaction_snapshot()
	if player.inventory.add_item(&"raw_meat", raw_meat_yield) != raw_meat_yield \
			or player.inventory.add_item(&"hide", hide_yield) != hide_yield:
		player.inventory.restore_transaction_snapshot(before)
		return false
	queue_free()
	return true


func smell_strength() -> float:
	return SPOILED_SMELL if state == State.SPOILED else BASE_SMELL


func get_smell_position() -> Vector2:
	return global_position


func apply_state(next_state: int, elapsed: float, meat: int, hide: int) -> void:
	state = clampi(next_state, State.ARMED, State.SPOILED)
	unattended_seconds = maxf(elapsed, 0.0)
	raw_meat_yield = maxi(meat, 0)
	hide_yield = maxi(hide, 0)
	_refresh_smell()


func _refresh_smell() -> void:
	if _grid == null:
		_grid = SmellGrid.find_in(get_tree())
	if _grid != null:
		_grid.register_smell_source(self, Callable(self, "get_smell_position"),
			smell_strength(), 1.0, &"snare")


func _exit_tree() -> void:
	if _grid != null:
		_grid.unregister_smell_source(self)

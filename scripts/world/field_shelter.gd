class_name FieldShelter
extends Area2D

signal rested(who: Player)

@export var rest_seconds: float = 6.0
@export var fatigue_recovery_multiplier: float = 8.0
var used: bool = false
var _grid: SmellGrid


func _ready() -> void:
	add_to_group(&"installation")
	add_to_group(&"field_shelter")
	_refresh_trace_smell.call_deferred()


func can_interact(who: Node) -> bool:
	return who is Player and not used


func get_hold_seconds() -> float:
	return rest_seconds


func get_prompt() -> String:
	return "야외 은신처에서 쉬기"


func on_hold_started(who: Node) -> void:
	var player := who as Player
	if player != null and multiplayer.is_server():
		player.stats.set_rest_multiplier(fatigue_recovery_multiplier)


func on_hold_ended(who: Node) -> void:
	var player := who as Player
	if player != null and multiplayer.is_server():
		player.stats.set_rest_multiplier(1.0)


func interact(who: Node) -> void:
	var player := who as Player
	if player == null or used:
		return
	if not multiplayer.is_server():
		var manager := get_tree().get_first_node_in_group(&"world_installations") as WorldInstallations
		if manager != null:
			manager.request_shelter_use(player, self)
		return
	use_authoritative(player)


func use_authoritative(player: Player) -> bool:
	if player == null or used or not multiplayer.is_server() \
			or player.global_position.distance_to(global_position) > 96.0:
		return false
	used = true
	modulate = Color(0.42, 0.38, 0.32, 0.75)
	_refresh_trace_smell()
	var recovery := player.stats.config.fatigue_recover_per_second \
		* fatigue_recovery_multiplier * rest_seconds
	player.stats.fatigue = maxf(player.stats.fatigue - recovery, 0.0)
	rested.emit(player)
	var save := get_tree().get_first_node_in_group(&"save_service") as SaveService
	if save != null:
		save.save_now(&"field_shelter")
	return true


func apply_state(was_used: bool) -> void:
	used = was_used
	modulate = Color(0.42, 0.38, 0.32, 0.75) if used else Color.WHITE
	_refresh_trace_smell()


func get_smell_position() -> Vector2:
	return global_position


func _refresh_trace_smell() -> void:
	if _grid == null:
		_grid = SmellGrid.find_in(get_tree())
	if _grid != null:
		_grid.register_smell_source(self, Callable(self, "get_smell_position"),
			14.0 if used else 3.0, 1.0, &"shelter_trace")


func _exit_tree() -> void:
	if _grid != null:
		_grid.unregister_smell_source(self)

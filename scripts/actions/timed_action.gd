class_name TimedAction
extends RefCounted

var definition: ActionDefinition
var elapsed_ticks: int = 0
var started: bool = false
var cancelled: bool = false
var committed: bool = false

func _init(value: ActionDefinition) -> void:
	definition = value

func start() -> bool:
	if started or definition == null or not definition.is_valid(): return false
	started = true
	return true

func tick() -> void:
	if started and not cancelled and not committed: elapsed_ticks += 1

func cancel() -> bool:
	if not started or committed: return false
	cancelled = true
	return true

func can_commit(ticks_per_second: int = 60) -> bool:
	return started and not cancelled and not committed and elapsed_ticks >= ceili(definition.duration * ticks_per_second)

func commit(ticks_per_second: int = 60) -> bool:
	if not can_commit(ticks_per_second): return false
	committed = true
	return true

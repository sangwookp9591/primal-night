class_name ActionController
extends Node

signal action_started(action)
signal action_cancelled(action)
signal action_completed(action)

var current_action: TimedAction = null
var actor: Node = null

func _ready() -> void:
	actor = get_parent()

func start(definition: ActionDefinition) -> bool:
	if current_action != null: return false
	var action := TimedAction.new(definition)
	if not action.start(): return false
	current_action = action
	if actor != null and "movement_locked" in actor: actor.movement_locked = true
	action_started.emit(action)
	return true

func _physics_process(_delta: float) -> void:
	if current_action != null: current_action.tick()

func cancel() -> bool:
	if current_action == null or not current_action.cancel(): return false
	_finish(false)
	return true

func commit() -> bool:
	if current_action == null or not current_action.commit(): return false
	_finish(true)
	return true

func _finish(done: bool) -> void:
	var action := current_action
	current_action = null
	if actor != null and "movement_locked" in actor: actor.movement_locked = false
	(action_completed if done else action_cancelled).emit(action)

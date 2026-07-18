class_name Bedding
extends Area2D

@export var rest_seconds: float = 6.0
@export var fatigue_recovery_multiplier: float = 8.0

func can_interact(who: Node) -> bool:
	return who is Player

func get_hold_seconds() -> float:
	return rest_seconds

func get_prompt() -> String:
	return "잠자리에서 쉬기"

func on_hold_started(who: Node) -> void:
	var player := who as Player
	var net := _net()
	if player != null and net != null:
		net.request_bedding(self, player, true, fatigue_recovery_multiplier)

func on_hold_ended(who: Node) -> void:
	var player := who as Player
	var net := _net()
	if player != null and net != null:
		net.request_bedding(self, player, false, fatigue_recovery_multiplier)

func interact(_who: Node) -> void:
	pass

func _net() -> NetBaseCamp:
	var root: Node = get_parent()
	while root != null and root.get_node_or_null("NetBaseCamp") == null:
		root = root.get_parent()
	return root.get_node_or_null("NetBaseCamp") as NetBaseCamp if root != null else null

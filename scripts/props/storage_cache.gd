class_name StorageCache
extends Area2D

@onready var inventory: Inventory = $Inventory

func can_interact(who: Node) -> bool:
	return who is Player

func get_hold_seconds() -> float:
	return 0.0

func get_prompt() -> String:
	return "보관함 열기"

func interact(who: Node) -> void:
	var player := who as Player
	if player == null:
		return
	var screen := _side_root().get_node_or_null("InventoryScreen") as InventoryScreen
	if screen != null:
		screen.open_storage(player, self)

func request_transfer(player: Player, item_id: StringName, to_storage: bool) -> void:
	var net := _side_root().get_node_or_null("NetBaseCamp") as NetBaseCamp
	if net != null:
		net.request_storage_transfer(self, player, item_id, to_storage)

func _side_root() -> Node:
	var root: Node = get_parent()
	while root != null and root.get_node_or_null("NetSession") == null:
		root = root.get_parent()
	return root

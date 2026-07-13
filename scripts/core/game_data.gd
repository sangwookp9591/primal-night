extends Node

const ItemData = preload("res://scripts/resources/item_data.gd")

func get_item(id: StringName) -> ItemData:
	push_error("Missing item data: %s" % id)
	return null

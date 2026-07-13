extends Node

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")

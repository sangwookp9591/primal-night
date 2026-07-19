extends Node

## 성능 오버레이 기본 숨김은 performance_overlay.gd 가 스스로 소유한다.

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# _ready 중 직접 호출하면 부모가 자식 추가 중이라 remove_child 에러가 난다.
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/title/title_screen.tscn")

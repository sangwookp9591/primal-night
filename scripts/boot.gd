extends Node

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	if DisplayServer.get_name() == "headless":
		return
	# _ready 중 직접 호출하면 부모가 자식 추가 중이라 remove_child 에러가 난다.
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/title/title_screen.tscn")


func _on_node_added(node: Node) -> void:
	if node.name == &"PerformanceOverlay":
		_hide_performance_overlay.call_deferred(node)


func _hide_performance_overlay(overlay: CanvasLayer) -> void:
	if not is_instance_valid(overlay):
		return
	# 성능 오버레이 자체의 기존 F3 핸들러는 유지하되 상용 기본값만 숨긴다.
	overlay.visible = false
	overlay.set_process(false)
	overlay.set("_visible_in_debug", false)

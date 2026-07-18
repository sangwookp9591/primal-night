extends SceneTree

## 수확 노드 흔들림 검증 프로브 (GUI 필요). 나무·열매 수풀을 화면에 놓고
## play_shake() 트윈의 3시점을 user://harvest_shake_{0,1,2}.png 로 덤프한다.
## 판정: 프레임 간 식물 기울기(회전)가 실제로 달라야 한다.

const HarvestScene: PackedScene = preload("res://scenes/items/harvestable_node.tscn")

func _init() -> void:
	await process_frame
	var root_node := Node2D.new()
	get_root().add_child(root_node)
	var camera := Camera2D.new()
	camera.zoom = Vector2(3, 3)
	root_node.add_child(camera)
	camera.make_current()

	var tree_node := HarvestScene.instantiate()
	tree_node.harvest_kind = "tree"
	tree_node.position = Vector2(-80, 20)
	root_node.add_child(tree_node)
	var bush := HarvestScene.instantiate()
	bush.harvest_kind = "berry_bush"
	bush.position = Vector2(80, 20)
	root_node.add_child(bush)

	await process_frame
	await process_frame
	await _capture(0)
	tree_node.play_shake()
	bush.play_shake()
	await create_timer(0.055).timeout
	await _capture(1)
	await create_timer(0.08).timeout
	await _capture(2)
	print("HARVEST_SHAKE_PROBE_DONE")
	quit(0)

func _capture(index: int) -> void:
	await process_frame
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png("user://harvest_shake_%d.png" % index)

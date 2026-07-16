extends GutTest

const MainScene: PackedScene = preload("res://scenes/main.tscn")


func test_main_scene_has_no_sense_playtest_items_or_floor_raw_meat_smell() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)

	assert_eq(_count_debug_items(main), 0, "일반 main.tscn 은 raw_meat/bait 디버그 오버레이를 싣지 않는다")
	var grid: SmellGrid = main.get_node("SmellGrid") as SmellGrid
	assert_eq(grid.get_registered_smell_source_count(), 0,
		"일반 main.tscn 에는 초기 raw_meat 바닥 냄새 원천이 없어야 한다")


func test_sense_playtest_scene_adds_only_reachable_raw_meat_and_bait_overlay() -> void:
	assert_true(ResourceLoader.exists("res://scenes/debug/sense_playtest.tscn"),
		"디버그 전용 sense_playtest.tscn 이 있어야 한다")
	if not ResourceLoader.exists("res://scenes/debug/sense_playtest.tscn"):
		return
	var packed: PackedScene = load("res://scenes/debug/sense_playtest.tscn") as PackedScene
	if packed == null:
		return

	var scene: Node = add_child_autofree(packed.instantiate())
	await wait_physics_frames(2)

	var raw_meat: WorldItem = scene.get_node_or_null("DebugSenseItems/RawMeat") as WorldItem
	var bait: WorldItem = scene.get_node_or_null("DebugSenseItems/Bait") as WorldItem
	assert_not_null(raw_meat, "디버그 판에는 도달 가능한 raw_meat 가 있어야 한다")
	assert_not_null(bait, "디버그 판에는 도달 가능한 bait 가 있어야 한다")
	if raw_meat == null or bait == null:
		return

	assert_eq(raw_meat.item_id, &"raw_meat")
	assert_eq(bait.item_id, &"bait")
	assert_lte(raw_meat.global_position.distance_to((scene.get_node("Player") as Player).global_position),
		NetPickup.PICKUP_MAX_DISTANCE_PX)
	assert_lte(bait.global_position.distance_to((scene.get_node("Player") as Player).global_position),
		NetPickup.PICKUP_MAX_DISTANCE_PX)
	assert_eq((scene.get_node("SmellGrid") as SmellGrid).get_registered_smell_source_count(), 1,
		"raw_meat 바닥 냄새 원천은 디버그 판에만 등록되어야 한다")


func _count_debug_items(root: Node) -> int:
	var count: int = 0
	for node: Node in _flatten(root):
		var item: WorldItem = node as WorldItem
		if item != null and (item.item_id == &"raw_meat" or item.item_id == &"bait"):
			count += 1
	return count


func _flatten(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	for child: Node in root.get_children():
		nodes.append_array(_flatten(child))
	return nodes

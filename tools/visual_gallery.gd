extends SceneTree

## 착용 장비 비주얼 평가용 갤러리. GUI 모드로 실행해 조합을 배치하고 PNG로 저장한다.
## 실행: godot --path . -s tools/visual_gallery.gd
## 산출: user://visual_gallery.png (절대 경로는 stdout에 출력)

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

const OUTFITS: Array[StringName] = [&"", &"white_underwear", &"work_clothes", &"leather_armor"]
const HANDS: Array[StringName] = [&"", &"stone_knife", &"stone_spear", &"bow", &"torch"]
const CELL: float = 96.0
const DIRECTION_VECTORS: Array[Vector2] = [
	Vector2(0, -1), Vector2(0.70710678, -0.70710678), Vector2(1, 0), Vector2(0.70710678, 0.70710678),
	Vector2(0, 1), Vector2(-0.70710678, 0.70710678), Vector2(-1, 0), Vector2(-0.70710678, -0.70710678),
]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var window: Window = get_root()
	window.size = Vector2i(1000, 1000)

	var background := ColorRect.new()
	background.color = Color(0.28, 0.30, 0.20)
	background.size = Vector2(1000, 1000)
	get_root().add_child(background)

	# 행: 의상 4종(맨몸 포함) × 8방향, 이어서 손 장비 4종(S방향, 의상=white_underwear)
	var row: int = 0
	for outfit: StringName in OUTFITS:
		for direction: int in range(8):
			var player := _spawn_player(outfit, &"", &"")
			player.global_position = Vector2(64.0 + direction * CELL, 72.0 + row * CELL)
			_face(player, direction)
		row += 1

	var hand_col: int = 0
	for hand: StringName in HANDS:
		if hand == &"":
			continue
		var player := _spawn_player(&"white_underwear", hand, &"placeholder_back")
		player.global_position = Vector2(112.0 + hand_col * 2.0 * CELL, 72.0 + row * CELL)
		_face(player, 4) # S
		hand_col += 1
	# 손 장비 E/W 방향 확인 행
	row += 1
	hand_col = 0
	for hand: StringName in [&"stone_spear", &"bow"]:
		for direction: int in [2, 6, 1, 5]: # E, W, NE, SW
			var player := _spawn_player(&"work_clothes", hand, &"")
			player.global_position = Vector2(64.0 + hand_col * CELL, 72.0 + row * CELL)
			_face(player, direction)
			hand_col += 1

	for i: int in range(12):
		await process_frame

	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path: String = "user://visual_gallery.png"
	image.save_png(path)
	print("GALLERY_SAVED: ", ProjectSettings.globalize_path(path))
	quit(0)


func _spawn_player(outfit: StringName, hand: StringName, back: StringName) -> Node2D:
	var player: Node2D = PlayerScene.instantiate()
	get_root().add_child(player)
	player.set_physics_process(false)
	var camera: Camera2D = player.get_node_or_null("Camera2D")
	if camera != null:
		camera.enabled = false
	var equipment: EquipmentComponent = player.get_node("EquipmentComponent")
	var inventory: Inventory = player.get_node("Inventory")
	# 시작 장비(white_underwear)를 지운 뒤 지정 조합만 장착한다.
	for slot: StringName in EquipmentComponent.SLOTS:
		if equipment.get_equipped(slot) != &"":
			equipment.apply_snapshot({
				outfit = &"", back = &"", main_hand = &"", condition_flags = 0,
			})
			break
	var snapshot: Dictionary = {
		outfit = outfit, back = &"", main_hand = hand, condition_flags = 0,
	}
	if not equipment.apply_snapshot(snapshot):
		push_error("장착 실패: %s/%s/%s" % [outfit, hand, back])
	if back != &"":
		var rig: PlayerVisualRig = player.get_node("VisualRig")
		if not rig.apply_visual(&"back", back):
			push_error("등 장비 비주얼 적용 실패: %s" % back)
	return player


func _face(player: Node2D, direction: int) -> void:
	var rig: PlayerVisualRig = player.get_node("VisualRig")
	rig.update_from_velocity(DIRECTION_VECTORS[direction] * 10.0, 0)
	rig.update_from_velocity(Vector2.ZERO, 0)

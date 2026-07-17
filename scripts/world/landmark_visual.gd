class_name LandmarkVisual
extends Node2D

const SHEET: Texture2D = preload("res://assets/sprites/landmarks/valley_landmarks_10_sheet.png")
const CELL_SIZE: Vector2i = Vector2i(128, 128)
const SHEET_COLUMNS: int = 5
const TILES_PER_CHUNK: int = 32
const GRID: int = 8
const LABEL_COLOR: Color = Color("#ECE3D2")
const LABEL_MUTED: Color = Color("#A89C84")
const AMBER: Color = Color("#E0A458")
const CYAN: Color = Color("#6FC7C9")
const DANGER: Color = Color("#D96A5C")

const LANDMARKS: Dictionary = {
	"S01": Vector2i(1, 1), "S02": Vector2i(2, 2), "S03": Vector2i(4, 2),
	"S04": Vector2i(5, 1), "S05": Vector2i(2, 5), "S06": Vector2i(3, 3),
	"S07": Vector2i(1, 4), "S08": Vector2i(4, 5), "S09": Vector2i(4, 4),
	"S10": Vector2i(3, 7), "F1": Vector2i(3, 2), "F2": Vector2i(3, 4),
	"F3": Vector2i(3, 5), "R1": Vector2i(5, 3), "R2": Vector2i(1, 5),
	"H1": Vector2i(5, 5),
}

const LANDMARK_LABELS: Dictionary = {
	"S01": "S01 균열 추락흔", "S02": "S02 현무암 바람막이", "S03": "S03 붉은 갈대 웅덩이",
	"S04": "S04 침수 관측소", "S05": "S05 울음 골", "S06": "S06 메아리 동굴",
	"S07": "S07 갈고리턱 둥지", "S08": "S08 방패뿔 산란환", "S09": "S09 무리 횡단 수로",
	"S10": "S10 검은 능선 신호대", "F1": "F1 모닥불 자리", "F2": "F2 마른 굴",
	"F3": "F3 서쪽 바람막이", "R1": "R1 낮은 여울", "R2": "R2 덩굴 절벽", "H1": "H1 해체 고보상",
}


func _ready() -> void:
	y_sort_enabled = true
	call_deferred("_build_landmarks")


static func sheet_index_for(landmark_id: String) -> int:
	if not landmark_id.begins_with("S"):
		return -1
	var index: int = landmark_id.substr(1).to_int() - 1
	return index if index >= 0 and index < 10 else -1


static func atlas_region_for(landmark_id: String) -> Rect2:
	var index: int = sheet_index_for(landmark_id)
	if index < 0:
		return Rect2()
	var column: int = index % SHEET_COLUMNS
	var row: int = index / SHEET_COLUMNS
	return Rect2(Vector2(column * CELL_SIZE.x, row * CELL_SIZE.y), CELL_SIZE)


static func atlas_texture_for(landmark_id: String) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = SHEET
	texture.region = atlas_region_for(landmark_id)
	return texture


static func chunk_cell_origin(doc_coord: Vector2i) -> Vector2i:
	var tile_row: int = (GRID - 1) - doc_coord.y
	return Vector2i(doc_coord.x * TILES_PER_CHUNK, tile_row * TILES_PER_CHUNK)


func _build_landmarks() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for landmark_id: String in LANDMARKS:
		var marker: Node2D = _make_landmark(landmark_id)
		add_child(marker)


func _make_landmark(landmark_id: String) -> Node2D:
	var marker := Node2D.new()
	marker.name = landmark_id
	marker.position = _local_position_for(landmark_id)
	marker.z_index = int(marker.position.y)
	if sheet_index_for(landmark_id) >= 0:
		_add_sprite(marker, landmark_id)
	else:
		_add_aux_marker(marker, landmark_id)
	_add_label(marker, landmark_id)
	return marker


func _local_position_for(landmark_id: String) -> Vector2:
	var ground: TileMapLayer = get_parent().get_node("Ground")
	var doc_coord: Vector2i = LANDMARKS[landmark_id]
	var center_cell: Vector2i = chunk_cell_origin(doc_coord) + Vector2i(TILES_PER_CHUNK / 2, TILES_PER_CHUNK / 2)
	return ground.map_to_local(center_cell)


func _add_sprite(marker: Node2D, landmark_id: String) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = atlas_texture_for(landmark_id)
	sprite.centered = true
	sprite.offset = Vector2(0.0, -CELL_SIZE.y / 2.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 0
	marker.add_child(sprite)


func _add_aux_marker(marker: Node2D, landmark_id: String) -> void:
	var diamond := Polygon2D.new()
	diamond.name = "Marker"
	diamond.polygon = PackedVector2Array([
		Vector2(0, -14), Vector2(20, 0), Vector2(0, 14), Vector2(-20, 0),
	])
	var kind: String = landmark_id.substr(0, 1)
	diamond.color = {
		"F": Color(0.90, 0.50, 0.25, 0.9),
		"R": Color(CYAN, 0.9),
		"H": Color(DANGER, 0.9),
	}.get(kind, Color(0.8, 0.8, 0.8, 0.9))
	diamond.z_index = 0
	marker.add_child(diamond)


func _add_label(marker: Node2D, landmark_id: String) -> void:
	var label := Label.new()
	label.name = "Label"
	label.text = LANDMARK_LABELS.get(landmark_id, landmark_id)
	label.position = Vector2(-42, -86) if sheet_index_for(landmark_id) >= 0 else Vector2(-24, -34)
	label.add_theme_color_override(&"font_color", LABEL_COLOR if landmark_id.begins_with("S") else LABEL_MUTED)
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.72))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	label.add_theme_font_size_override(&"font_size", 11)
	label.z_index = 20
	marker.add_child(label)

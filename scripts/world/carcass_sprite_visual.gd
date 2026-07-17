class_name CarcassSpriteVisual
extends Sprite2D

const SHEET: Texture2D = preload("res://assets/sprites/creatures/raptor_carcass_stages_sheet.png")
const CELL_SIZE: Vector2i = Vector2i(64, 64)
const DIRECTION_COUNT: int = 8
const STAGE_COUNT: int = 4

enum Direction { N, NE, E, SE, S, SW, W, NW }
enum Stage { INTACT, PARTIAL, MOSTLY, COMPLETE }

var visual_direction: int = Direction.S
var visual_stage: int = Stage.INTACT


func _ready() -> void:
	centered = true
	offset = Vector2(0.0, -CELL_SIZE.y / 2.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	apply_visual(visual_direction, visual_stage)


static func stage_for_progress(done: int, total: int = 4) -> int:
	if done <= 0:
		return Stage.INTACT
	if done >= total:
		return Stage.COMPLETE
	if done == 1:
		return Stage.PARTIAL
	return Stage.MOSTLY


static func atlas_frame(direction: int, stage: int) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = SHEET
	frame.region = Rect2(
		Vector2(
			wrapi(direction, 0, DIRECTION_COUNT) * CELL_SIZE.x,
			clampi(stage, 0, STAGE_COUNT - 1) * CELL_SIZE.y),
		CELL_SIZE)
	return frame


func apply_visual(direction: int, stage: int) -> void:
	visual_direction = wrapi(direction, 0, DIRECTION_COUNT)
	visual_stage = clampi(stage, 0, STAGE_COUNT - 1)
	texture = atlas_frame(visual_direction, visual_stage)

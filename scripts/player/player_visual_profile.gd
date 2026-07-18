class_name PlayerVisualProfile
extends RefCounted

const CELL_SIZE := Vector2i(48, 64)
const DIRECTION_COUNT := 8
const IDLE_FRAME_COUNT := 2
const WALK_FRAME_COUNT := 4

const VISUALS: Dictionary = {
	&"white_underwear": {
		layer = &"outfit",
		color = Color(0.88, 0.91, 0.94, 0.72),
		sheet = "res://assets/sprites/player/equipment/white_underwear_sheet.png",
	},
	&"work_clothes": {
		layer = &"outfit",
		color = Color(0.28, 0.38, 0.22, 0.88),
		sheet = "res://assets/sprites/player/equipment/work_clothes_sheet.png",
	},
	&"leather_armor": {
		layer = &"outfit",
		color = Color(0.30, 0.17, 0.09, 0.94),
		sheet = "res://assets/sprites/player/equipment/leather_armor_sheet.png",
	},
	&"fur_cloak": {
		layer = &"outfit",
		color = Color(0.45, 0.32, 0.2, 0.96),
		sheet = "res://assets/sprites/player/equipment/fur_cloak_sheet.png",
	},
	&"reed_raincoat": {
		layer = &"outfit",
		color = Color(0.55, 0.56, 0.2, 0.96),
		sheet = "res://assets/sprites/player/equipment/reed_raincoat_sheet.png",
	},
	&"bone_armor": {
		layer = &"outfit",
		color = Color(0.78, 0.73, 0.56, 0.98),
		sheet = "res://assets/sprites/player/equipment/bone_armor_sheet.png",
	},
	&"placeholder_back": {
		layer = &"back",
		color = Color(0.27, 0.18, 0.10, 0.9),
		sheet = "res://assets/sprites/player/equipment/placeholder_back_sheet.png",
	},
	&"placeholder_main_hand": {
		layer = &"main_hand",
		color = Color(0.55, 0.62, 0.68, 0.95),
	},
	&"stone_spear": {
		layer = &"main_hand",
		color = Color(0.46, 0.31, 0.16, 1.0),
		sheet = "res://assets/sprites/player/equipment/stone_spear_sheet.png",
	},
	&"stone_knife": {
		layer = &"main_hand",
		color = Color(0.62, 0.67, 0.70, 1.0),
		sheet = "res://assets/sprites/player/equipment/stone_knife_sheet.png",
	},
	&"bow": {
		layer = &"main_hand",
		color = Color(0.58, 0.36, 0.16, 1.0),
		sheet = "res://assets/sprites/player/equipment/bow_sheet.png",
	},
	&"torch": {
		layer = &"main_hand",
		color = Color(0.82, 0.39, 0.12, 1.0),
		sheet = "res://assets/sprites/player/equipment/torch_sheet.png",
	},
	&"placeholder_state_overlay": {
		layer = &"state_overlay",
		color = Color(0.25, 0.65, 1.0, 0.35),
	},
	&"poison_state": {
		layer = &"state_overlay",
		color = Color(0.46, 0.62, 0.42, 0.9),
		sheet = "res://assets/sprites/player/states/poison_state_sheet.png",
	},
	&"food_poison_state": {
		layer = &"state_overlay",
		color = Color(0.72, 0.62, 0.25, 0.9),
		sheet = "res://assets/sprites/player/states/food_poison_state_sheet.png",
	},
}

# Backpack-like visuals are behind the body when facing the camera and over it
# when the character faces away. Keeping the complete table here makes the
# eight-direction draw contract inspectable without screenshots.
const Z_ORDER_BY_DIRECTION: Array[Dictionary] = [
	{base_body = 0, outfit = 1, back = 2, main_hand = 3, state_overlay = 4}, # N
	{base_body = 0, outfit = 1, back = 2, main_hand = 3, state_overlay = 4}, # NE
	{base_body = 0, outfit = 1, back = -1, main_hand = 3, state_overlay = 4}, # E
	{base_body = 0, outfit = 1, back = -1, main_hand = 3, state_overlay = 4}, # SE
	{base_body = 0, outfit = 1, back = -1, main_hand = 3, state_overlay = 4}, # S
	{base_body = 0, outfit = 1, back = -1, main_hand = 3, state_overlay = 4}, # SW
	{base_body = 0, outfit = 1, back = -1, main_hand = 3, state_overlay = 4}, # W
	{base_body = 0, outfit = 1, back = 2, main_hand = 3, state_overlay = 4}, # NW
]


static func registered_visual_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for visual_id: StringName in VISUALS:
		ids.append(visual_id)
	return ids


static func has_visual(visual_id: StringName) -> bool:
	return VISUALS.has(visual_id)


static func layer_for_visual(visual_id: StringName) -> StringName:
	if not VISUALS.has(visual_id):
		return &""
	return StringName(VISUALS[visual_id].layer)


static func z_order(direction: int) -> Dictionary:
	if direction < 0 or direction >= Z_ORDER_BY_DIRECTION.size():
		direction = PlayerSpriteAnimator.Direction.S
	return Z_ORDER_BY_DIRECTION[direction]


static func build_frames(visual_id: StringName) -> SpriteFrames:
	if not VISUALS.has(visual_id):
		return null
	var result := SpriteFrames.new()
	result.remove_animation(&"default")
	var color: Color = VISUALS[visual_id].color
	var sheet: Texture2D = _load_sheet(visual_id)
	for direction: int in range(DIRECTION_COUNT):
		_add_animation(result, visual_id, color, sheet, false, direction, IDLE_FRAME_COUNT, 2.0)
		_add_animation(result, visual_id, color, sheet, true, direction, WALK_FRAME_COUNT, 8.0)
	return result


static func has_registered_sheet(visual_id: StringName) -> bool:
	if not VISUALS.has(visual_id) or not VISUALS[visual_id].has("sheet"):
		return false
	return ResourceLoader.exists(String(VISUALS[visual_id].sheet), "Texture2D")


static func has_complete_frame_keys(visual_id: StringName) -> bool:
	var frames := build_frames(visual_id)
	if frames == null:
		return false
	for direction: int in range(DIRECTION_COUNT):
		for walking: bool in [false, true]:
			var animation := PlayerSpriteAnimator.animation_name(walking, direction)
			var expected := WALK_FRAME_COUNT if walking else IDLE_FRAME_COUNT
			if not frames.has_animation(animation) or frames.get_frame_count(animation) != expected:
				return false
	return true


static func _add_animation(
		frames: SpriteFrames,
		visual_id: StringName,
		color: Color,
		sheet: Texture2D,
		walking: bool,
		direction: int,
		frame_count: int,
		speed: float) -> void:
	var animation := PlayerSpriteAnimator.animation_name(walking, direction)
	frames.add_animation(animation)
	frames.set_animation_loop(animation, true)
	frames.set_animation_speed(animation, speed)
	for frame_index: int in range(frame_count):
		var row: int = frame_index + (IDLE_FRAME_COUNT if walking else 0)
		var texture: Texture2D = _atlas_frame(sheet, direction, row) if sheet != null else \
				_placeholder_texture(visual_id, color, direction, frame_index)
		frames.add_frame(animation, texture)


static func _load_sheet(visual_id: StringName) -> Texture2D:
	if not has_registered_sheet(visual_id):
		return null
	return load(String(VISUALS[visual_id].sheet)) as Texture2D


static func _atlas_frame(sheet: Texture2D, column: int, row: int) -> Texture2D:
	var frame := AtlasTexture.new()
	frame.atlas = sheet
	frame.region = Rect2(Vector2(column * CELL_SIZE.x, row * CELL_SIZE.y), CELL_SIZE)
	return frame


static func _placeholder_texture(
		visual_id: StringName,
		color: Color,
		direction: int,
		frame_index: int) -> Texture2D:
	var image := Image.create(CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var bob: int = frame_index % 2
	var rect := Rect2i(15, 25 + bob, 18, 25)
	match layer_for_visual(visual_id):
		&"outfit":
			rect = Rect2i(14, 35 + bob, 20, 14)
		&"back":
			rect = Rect2i(12 if direction in [1, 2, 3] else 22, 23 + bob, 14, 27)
		&"main_hand":
			rect = Rect2i(34 if direction in [1, 2, 3, 4] else 8, 27 + bob, 5, 25)
		&"state_overlay":
			rect = Rect2i(10, 14 + bob, 28, 40)
	image.fill_rect(rect, color)
	return ImageTexture.create_from_image(image)

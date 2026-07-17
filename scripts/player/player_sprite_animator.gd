class_name PlayerSpriteAnimator
extends AnimatedSprite2D

const SHEET: Texture2D = preload("res://assets/sprites/player/player_survivor_sheet.png")
const CELL_SIZE: Vector2i = Vector2i(48, 64)
const DIRECTION_COUNT: int = 8
const IDLE_ROWS: Array[int] = [0, 1]
const WALK_ROWS: Array[int] = [2, 3, 4, 5]
const RUN_SPEED_SCALE: float = 1.5
const CROUCH_SPEED_SCALE: float = 0.6
const STANCE_RUN: int = 1
const STANCE_CROUCH: int = 2

enum Direction { N, NE, E, SE, S, SW, W, NW }

const DIRECTION_NAMES: Array[StringName] = [
	&"N", &"NE", &"E", &"SE", &"S", &"SW", &"W", &"NW",
]
const ANGLE_SECTOR_TO_DIRECTION: Array[int] = [
	Direction.E, Direction.SE, Direction.S, Direction.SW,
	Direction.W, Direction.NW, Direction.N, Direction.NE,
]

var last_direction: int = Direction.S


func _ready() -> void:
	centered = true
	offset = Vector2(0.0, -CELL_SIZE.y / 2.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_frames = build_sprite_frames()
	play(animation_name(false, last_direction))


static func direction_for_vector(vector: Vector2) -> int:
	if vector.is_zero_approx():
		return Direction.S
	var sector: int = wrapi(roundi(vector.angle() / (PI / 4.0)), 0, DIRECTION_COUNT)
	return ANGLE_SECTOR_TO_DIRECTION[sector]


static func direction_name(direction: int) -> StringName:
	if direction < 0 or direction >= DIRECTION_NAMES.size():
		return &"S"
	return DIRECTION_NAMES[direction]


static func animation_name(walking: bool, direction: int) -> StringName:
	var prefix: String = "walk" if walking else "idle"
	return StringName("%s_%s" % [prefix, direction_name(direction)])


static func build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for direction: int in range(DIRECTION_COUNT):
		_add_animation(frames, false, direction, IDLE_ROWS, 2.0)
		_add_animation(frames, true, direction, WALK_ROWS, 8.0)
	return frames


static func _add_animation(
		frames: SpriteFrames,
		walking: bool,
		direction: int,
		rows: Array[int],
		speed: float) -> void:
	var anim: StringName = animation_name(walking, direction)
	frames.add_animation(anim)
	frames.set_animation_loop(anim, true)
	frames.set_animation_speed(anim, speed)
	for row: int in rows:
		frames.add_frame(anim, _atlas_frame(direction, row))


static func _atlas_frame(column: int, row: int) -> Texture2D:
	var frame := AtlasTexture.new()
	frame.atlas = SHEET
	frame.region = Rect2(Vector2(column * CELL_SIZE.x, row * CELL_SIZE.y), CELL_SIZE)
	return frame


func update_from_velocity(player_velocity: Vector2, stance: int) -> void:
	var walking: bool = not player_velocity.is_zero_approx()
	if walking:
		last_direction = direction_for_vector(player_velocity)
	var next_animation: StringName = animation_name(walking, last_direction)
	if animation != next_animation:
		play(next_animation)
	speed_scale = speed_scale_for_stance(stance) if walking else 1.0


func speed_scale_for_stance(stance: int) -> float:
	match stance:
		STANCE_RUN:
			return RUN_SPEED_SCALE
		STANCE_CROUCH:
			return CROUCH_SPEED_SCALE
		_:
			return 1.0

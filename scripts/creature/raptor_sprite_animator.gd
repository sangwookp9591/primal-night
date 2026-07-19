class_name RaptorSpriteAnimator
extends AnimatedSprite2D

const SHEET: Texture2D = preload("res://assets/sprites/creatures/raptor_idle_walk_sheet.png")
const CELL_SIZE: Vector2i = Vector2i(96, 80)
const DIRECTION_COUNT: int = 8
const IDLE_ROWS: Array[int] = [0, 1]
const WALK_ROWS: Array[int] = [2, 3, 4, 5]
const WALK_REFERENCE_SPEED: float = 55.0
const CHASE_SPEED_SCALE: float = 3.0
const STATE_CHASE: int = 2

enum Direction { N, NE, E, SE, S, SW, W, NW }

const DIRECTION_NAMES: Array[StringName] = [
	&"N", &"NE", &"E", &"SE", &"S", &"SW", &"W", &"NW",
]
const ANGLE_SECTOR_TO_DIRECTION: Array[int] = [
	Direction.E, Direction.SE, Direction.S, Direction.SW,
	Direction.W, Direction.NW, Direction.N, Direction.NE,
]

var last_direction: int = Direction.S
var _telegraph_direction: Vector2 = Vector2.ZERO
var _telegraphing: bool = false
var _sniffing: bool = false
var _sniff_elapsed: float = 0.0


func _ready() -> void:
	centered = true
	offset = Vector2(0.0, -CELL_SIZE.y / 2.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_frames = build_sprite_frames()
	play(animation_name(false, last_direction))
	set_process(false)


func _process(delta: float) -> void:
	if not _sniffing:
		return
	_sniff_elapsed += delta
	# 새 시트 대신 기존 8방향 idle을 천천히 훑어 머리를 들고 냄새 방향을 찾는 몸짓.
	last_direction = wrapi(last_direction + (1 if _sniff_elapsed >= 0.18 else 0), 0, DIRECTION_COUNT)
	if _sniff_elapsed >= 0.18:
		_sniff_elapsed = 0.0
	var sniff_animation: StringName = animation_name(false, last_direction)
	if animation != sniff_animation:
		play(sniff_animation)


func begin_sense_telegraph(kind: StringName, direction: Vector2) -> void:
	_telegraph_direction = direction
	_telegraphing = true
	_sniffing = kind == &"smell"
	_sniff_elapsed = 0.0
	set_process(_sniffing)
	if not direction.is_zero_approx():
		last_direction = direction_for_vector(direction)
	play(animation_name(false, last_direction))


func end_sense_telegraph() -> void:
	_telegraphing = false
	_sniffing = false
	set_process(false)


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
		_add_animation(frames, false, direction, IDLE_ROWS, 1.5)
		_add_animation(frames, true, direction, WALK_ROWS, 5.0)
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


func update_from_velocity(raptor_velocity: Vector2, raptor_state: int) -> void:
	if _telegraphing:
		return
	var walking: bool = not raptor_velocity.is_zero_approx()
	if walking:
		last_direction = direction_for_vector(raptor_velocity)
	var next_animation: StringName = animation_name(walking, last_direction)
	if animation != next_animation:
		play(next_animation)
	if not walking:
		speed_scale = 1.0
	elif raptor_state == STATE_CHASE:
		speed_scale = CHASE_SPEED_SCALE
	else:
		speed_scale = clampf(raptor_velocity.length() / WALK_REFERENCE_SPEED, 0.75, 1.25)

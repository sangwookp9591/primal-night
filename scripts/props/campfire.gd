class_name Campfire
extends Node2D

## 모닥불. 연료가 떨어지면 꺼진다 (단순 타이머).
## light_radius 는 T4 의 랩터가 회피 판단에 쓴다.
## 타는 동안에만 _process 를 켠다 (성능문서 6.1).

const DEFAULT_CONFIG: CampfireConfig = preload("res://data/props/campfire_config.tres")
const STATE_SHEET: Texture2D = preload("res://assets/sprites/props/campfire_states_sheet.png")
const CELL_SIZE := Vector2(128.0, 128.0)

@export var config: CampfireConfig = DEFAULT_CONFIG

var is_lit: bool = false
var fuel_remaining: float = 0.0

var _event_bus: Node = null
var _registry: Node = null

func _ready() -> void:
	add_to_group(&"campfire")
	_configure_visual()
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	if has_node("/root/CampfireRegistry"):
		_registry = get_node("/root/CampfireRegistry")
	set_process(false)

func _configure_visual() -> void:
	var sprite := get_node_or_null("CampfireSprite") as AnimatedSprite2D
	if sprite == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"unlit")
	frames.add_frame(&"unlit", _frame_texture(0))
	frames.add_animation(&"lit")
	frames.set_animation_loop(&"lit", true)
	frames.set_animation_speed(&"lit", 6.0)
	for index: int in range(1, 4):
		frames.add_frame(&"lit", _frame_texture(index))
	sprite.sprite_frames = frames
	sprite.play(&"lit" if is_lit else &"unlit")

static func _frame_texture(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = STATE_SHEET
	atlas.region = Rect2(Vector2(index * CELL_SIZE.x, 0.0), CELL_SIZE)
	return atlas

func _process(delta: float) -> void:
	if not is_lit:
		return

	fuel_remaining = maxf(fuel_remaining - delta, 0.0)
	if fuel_remaining <= 0.0:
		extinguish()

func light() -> void:
	if is_lit:
		return

	is_lit = true
	fuel_remaining = config.fuel_seconds
	var sprite := get_node_or_null("CampfireSprite") as AnimatedSprite2D
	if sprite != null:
		sprite.play(&"lit")
	# 연료 소진 타이머는 호스트 소유 (설계서 7.2). 클라이언트 복제본은 타이머를
	# 돌리지 않고 NetCampfire 의 소등 복제만 받는다 (W2-T5).
	set_process(multiplayer.is_server())
	if _registry != null and multiplayer.is_server():
		_registry.register_fire(self, global_position, config.light_radius)
	# campfire_lit/extinguished 는 호스트에서만 발신한다 — 클라이언트 복제본도
	# 발신하면 랩터(호스트 소유 AI)가 불을 2개로 인식한다 (tests/props/test_net_campfire.gd).
	if _event_bus != null and multiplayer.is_server():
		_event_bus.campfire_lit.emit(self, global_position, config.light_radius)

func extinguish() -> void:
	if not is_lit:
		return

	is_lit = false
	fuel_remaining = 0.0
	var sprite := get_node_or_null("CampfireSprite") as AnimatedSprite2D
	if sprite != null:
		sprite.play(&"unlit")
	set_process(false)
	if _registry != null:
		_registry.unregister_fire(self)
	if _event_bus != null and multiplayer.is_server():
		_event_bus.campfire_extinguished.emit(self)

func get_radius() -> float:
	return config.light_radius


func _exit_tree() -> void:
	if _registry != null:
		_registry.unregister_fire(self)

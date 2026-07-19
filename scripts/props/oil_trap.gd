class_name OilTrap
extends Area2D

const SHEET: Texture2D = preload("res://assets/sprites/props/oil_trap_states_sheet.png")
const FLAME_SECONDS: float = 8.0
const FIRE_RADIUS: float = 112.0
const DAMAGE_PER_SECOND: float = 14.0
const SMOKE_LURE_RADIUS: float = 720.0

var ignited: bool = false
var flame_remaining: float = 0.0
var _registry: Node = null
var _event_bus: Node = null
var _warm_light: PointLight2D


func _ready() -> void:
	add_to_group(&"oil_trap")
	_registry = get_node_or_null("/root/CampfireRegistry")
	_event_bus = get_node_or_null("/root/EventBus")
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FIRE_RADIUS
	shape.shape = circle
	add_child(shape)
	var sprite := Sprite2D.new()
	sprite.name = "OilTrapSprite"
	sprite.texture = _frame(0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_warm_light = AtmosphereController.create_point_light(self, "WarmLight", 1.55, 0.95)
	_warm_light.enabled = false
	set_process(multiplayer.is_server())


static func install(parent: Node, player: Player, at: Vector2) -> OilTrap:
	if parent == null or player == null or not player.multiplayer.is_server():
		return null
	if not player.inventory.remove_item(&"oil_trap", 1):
		return null
	var trap := OilTrap.new()
	parent.add_child(trap)
	trap.global_position = at
	return trap


static func install_replica(parent: Node, player: Player, at: Vector2) -> OilTrap:
	if parent == null or player == null or not player.inventory.remove_item(&"oil_trap", 1):
		return null
	var trap := OilTrap.new()
	parent.add_child(trap)
	trap.global_position = at
	return trap


func can_ignite(player: Player = null) -> bool:
	if ignited:
		return false
	if player != null and player.equipment.get_equipped(&"main_hand") == &"torch":
		return true
	return _registry != null and _registry.is_position_protected(global_position, 1.25)


func ignite(player: Player = null) -> bool:
	if not multiplayer.is_server() or not can_ignite(player):
		return false
	_apply_ignited_visual()
	if multiplayer.get_peers().size() > 0:
		confirm_ignite.rpc()
	return true


func _apply_ignited_visual() -> void:
	ignited = true
	if _warm_light != null:
		_warm_light.enabled = true
	flame_remaining = FLAME_SECONDS
	($OilTrapSprite as Sprite2D).texture = _frame(1)
	if _registry != null and multiplayer.is_server():
		_registry.register_fire(self, global_position, FIRE_RADIUS)
	if _event_bus != null and multiplayer.is_server():
		_event_bus.noise_emitted.emit(global_position, SMOKE_LURE_RADIUS, self)


@rpc("authority", "call_remote", "reliable")
func confirm_ignite() -> void:
	if not multiplayer.is_server():
		_apply_ignited_visual()


func _process(delta: float) -> void:
	if not ignited:
		if can_ignite():
			ignite()
		return
	flame_remaining = maxf(flame_remaining - delta, 0.0)
	for body: Node2D in get_overlapping_bodies():
		apply_flame_damage(body, delta)
	if flame_remaining <= 0.0:
		extinguish()


func apply_flame_damage(body: Node, delta: float) -> void:
	var player := body as Player
	if ignited and player != null and player.health.is_alive():
		player.health.take_damage(DAMAGE_PER_SECOND * maxf(delta, 0.0))


func extinguish() -> void:
	if not ignited:
		return
	ignited = false
	if _warm_light != null:
		_warm_light.enabled = false
	flame_remaining = 0.0
	($OilTrapSprite as Sprite2D).texture = _frame(0)
	if _registry != null:
		_registry.unregister_fire(self)
	if multiplayer.is_server() and multiplayer.get_peers().size() > 0:
		confirm_extinguish.rpc()


@rpc("authority", "call_remote", "reliable")
func confirm_extinguish() -> void:
	if not multiplayer.is_server():
		ignited = false
		if _warm_light != null:
			_warm_light.enabled = false
		flame_remaining = 0.0
		($OilTrapSprite as Sprite2D).texture = _frame(0)


static func _frame(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEET
	atlas.region = Rect2(index * 128.0, 0.0, 128.0, 128.0)
	return atlas


func _exit_tree() -> void:
	if _registry != null:
		_registry.unregister_fire(self)

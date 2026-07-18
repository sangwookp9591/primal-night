class_name PlayerVisualRig
extends Node2D

const SLOT_TO_LAYER: Dictionary = {
	&"outfit": &"outfit",
	&"back": &"back",
	&"main_hand": &"main_hand",
}

@export var equipment_path: NodePath = ^"../EquipmentComponent"

@onready var base_body: PlayerSpriteAnimator = %BaseBody
@onready var outfit: AnimatedSprite2D = %Outfit
@onready var back: AnimatedSprite2D = %Back
@onready var main_hand: AnimatedSprite2D = %MainHand
@onready var state_overlay: AnimatedSprite2D = %StateOverlay

var _equipment: EquipmentComponent = null


func _ready() -> void:
	_equipment = get_node_or_null(equipment_path) as EquipmentComponent
	# All layers use the same 48x64 atlas coordinate system. BaseBody applies
	# this offset in PlayerSpriteAnimator._ready(); mirror it here or overlays
	# render exactly half a cell (32 px) below the character.
	for layer: AnimatedSprite2D in [outfit, back, main_hand, state_overlay]:
		layer.centered = base_body.centered
		layer.offset = base_body.offset
	base_body.frame_changed.connect(_sync_layers)
	base_body.animation_changed.connect(_sync_layers)
	if _equipment != null:
		_equipment.equipment_changed.connect(_on_equipment_changed)
		for slot: StringName in EquipmentComponent.SLOTS:
			_on_equipment_changed(slot, _equipment.get_equipped(slot))
	_sync_layers()


func update_from_velocity(player_velocity: Vector2, stance: int) -> void:
	base_body.update_from_velocity(player_velocity, stance)
	# Animation changes are signalled immediately; this also makes direct,
	# same-tick callers deterministic even when the frame number remains zero.
	_sync_layers()


func apply_visual(layer_name: StringName, visual_id: StringName) -> bool:
	var layer := get_layer(layer_name)
	if layer == null:
		push_warning("PlayerVisualRig: unknown visual layer %s" % layer_name)
		return false
	if visual_id == &"":
		layer.sprite_frames = null
		layer.visible = false
		return true
	if not PlayerVisualProfile.has_visual(visual_id):
		push_warning("PlayerVisualRig: missing visual_id %s for layer %s; hiding layer" % [
			visual_id, layer_name])
		layer.sprite_frames = null
		layer.visible = false
		return false
	if PlayerVisualProfile.layer_for_visual(visual_id) != layer_name:
		push_warning("PlayerVisualRig: visual_id %s does not belong to layer %s; hiding layer" % [
			visual_id, layer_name])
		layer.sprite_frames = null
		layer.visible = false
		return false
	layer.sprite_frames = PlayerVisualProfile.build_frames(visual_id)
	layer.visible = true
	_sync_layer(layer)
	return true


func get_layer(layer_name: StringName) -> AnimatedSprite2D:
	match layer_name:
		&"base_body":
			return base_body
		&"outfit":
			return outfit
		&"back":
			return back
		&"main_hand":
			return main_hand
		&"state_overlay":
			return state_overlay
		_:
			return null


func _on_equipment_changed(slot: StringName, item_id: StringName) -> void:
	if not SLOT_TO_LAYER.has(slot):
		return
	var layer_name: StringName = SLOT_TO_LAYER[slot]
	if item_id == &"":
		apply_visual(layer_name, &"")
		return
	var item: ItemData = get_node("/root/GameData").get_item(item_id) as ItemData
	if not item is WearableData:
		push_warning("PlayerVisualRig: equipped item %s has no wearable visual; hiding layer" % item_id)
		apply_visual(layer_name, &"")
		return
	apply_visual(layer_name, (item as WearableData).visual_id)


func _sync_layers() -> void:
	for layer: AnimatedSprite2D in [outfit, back, main_hand, state_overlay]:
		_sync_layer(layer)
	var order := PlayerVisualProfile.z_order(base_body.last_direction)
	base_body.z_index = order.base_body
	outfit.z_index = order.outfit
	back.z_index = order.back
	main_hand.z_index = order.main_hand
	state_overlay.z_index = order.state_overlay


func _sync_layer(layer: AnimatedSprite2D) -> void:
	if layer.sprite_frames == null or not layer.sprite_frames.has_animation(base_body.animation):
		return
	layer.animation = base_body.animation
	layer.set_frame_and_progress(
		mini(base_body.frame, layer.sprite_frames.get_frame_count(layer.animation) - 1),
		base_body.frame_progress)

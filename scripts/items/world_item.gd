class_name WorldItem
extends Area2D

## 월드에 떨어진 아이템. 상호작용으로 즉시 줍는다.
## 자리가 부족하면 들어간 만큼만 줄이고 나머지는 월드에 남긴다 (복제·소실 금지).

const PICKUP_NOISE: NoiseProfile = preload("res://data/senses/noise_harvest.tres")
const ITEM_SHEET: Texture2D = preload("res://assets/sprites/items/world_items_13_sheet.png")
const ITEM_CELL_SIZE := Vector2(64.0, 128.0)
const ITEM_ATLAS_INDICES := {
	&"stone": 0,
	&"wood": 1,
	&"fiber": 2,
	&"bone": 3,
	&"sinew": 4,
	&"raw_meat": 5,
	&"bandage": 6,
	&"bait": 7,
	&"smartphone": 8,
	&"stone_knife": 9,
	&"torch": 10,
	&"bone_scraper": 11,
	&"noise_lure": 12,
	&"hide": 13,
	&"berry": 14,
	&"mushroom": 15,
	&"toxic_mushroom": 16,
	&"cooked_meat": 17,
	&"bone_flute": 18,
	&"bait_pouch": 19,
	&"waterskin": 20,
	&"herb": 21,
	&"antidote_salad": 22,
	&"marrow_soup": 23,
	&"tallow": 24,
	&"charcoal": 25,
	&"oil_trap": 26,
	&"snare_kit": 27,
	&"shelter_kit": 28,
}

@export var item_id: StringName = &"stone"
@export var count: int = 1

var resource_respawn_seconds: float = 0.0
var _event_bus: Node = null
var _net_pickup: NetPickup = null
var _net_pickup_cached: bool = false
var _noise_emitter: NoiseEmitter = NoiseEmitter.new()
var _floor_smell_source: SmellSource = null
var _base_spawn_count: int = 0
var _respawn_count: int = 0
var _respawn_remaining: float = 0.0

func _ready() -> void:
	add_to_group(&"world_item")
	_base_spawn_count = count
	_respawn_count = count
	var item_sprite := get_node_or_null("ItemSprite") as Sprite2D
	if item_sprite != null:
		item_sprite.texture = icon_texture(item_id)
		if item_id == &"arrow":
			item_sprite.visible = false
			var marker := get_node_or_null("Marker") as ColorRect
			if marker != null:
				marker.visible = true
				marker.color = Color(0.83, 0.68, 0.35)
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	var item: ItemData = get_node("/root/GameData").get_item(item_id)
	if item != null and item.is_smell_source():
		_floor_smell_source = SmellSource.new()
		_floor_smell_source.kind = item.get_smell_kind()
		_floor_smell_source.strength = item.smell_strength
		_floor_smell_source.interval_seconds = item.smell_interval_seconds
		add_child(_floor_smell_source)
	set_process(false)

func _process(delta: float) -> void:
	if not multiplayer.is_server() or count > 0 or resource_respawn_seconds <= 0.0:
		return
	_respawn_remaining = maxf(_respawn_remaining - delta, 0.0)
	if _respawn_remaining > 0.0:
		return
	_restore_resource()
	if multiplayer.get_peers().size() > 0:
		receive_resource_respawn.rpc(count)

func apply_spawn_quantity_multiplier(multiplier: float) -> void:
	count = maxi(1, roundi(float(_base_spawn_count) * multiplier))
	_respawn_count = count

## 씬에 배치된 자원만 DifficultyRuntime 이 등록한다. 플레이어 사망 드롭처럼
## 런타임에 생성된 WorldItem 은 등록하지 않으므로 다시 생겨나지 않는다.
func configure_resource_respawn(base_seconds: float, time_multiplier: float) -> void:
	resource_respawn_seconds = maxf(base_seconds * maxf(time_multiplier, 0.0), 0.0)

func deplete() -> void:
	count = 0
	_clear_floor_smell_source()
	if resource_respawn_seconds <= 0.0:
		queue_free()
		return
	visible = false
	monitorable = false
	_respawn_remaining = resource_respawn_seconds
	set_process(multiplayer.is_server())

func _restore_resource() -> void:
	count = maxi(_respawn_count, 1)
	visible = true
	monitorable = true
	set_process(false)
	_restore_floor_smell_source()

@rpc("authority", "call_remote", "reliable")
func receive_resource_respawn(restored_count: int) -> void:
	if multiplayer.is_server() or restored_count <= 0:
		return
	count = restored_count
	visible = true
	monitorable = true

func respawn_remaining_seconds() -> float:
	return _respawn_remaining

static func atlas_index_for(id: StringName) -> int:
	if id == &"waterskin_full" or id == &"waterskin_half":
		return int(ITEM_ATLAS_INDICES[&"waterskin"])
	return int(ITEM_ATLAS_INDICES.get(id, -1))

static func icon_texture(id: StringName) -> AtlasTexture:
	var index := atlas_index_for(id)
	if index < 0:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = ITEM_SHEET
	atlas.region = Rect2(Vector2(index * ITEM_CELL_SIZE.x, 0.0), ITEM_CELL_SIZE)
	return atlas

func can_interact(who: Node) -> bool:
	return count > 0 and who is Player

func get_hold_seconds() -> float:
	return 0.0

func get_prompt() -> String:
	# 표시 문구는 ItemData 에서 만든다 (설계서 5.6: UI 하드코딩 금지).
	var item: ItemData = get_node("/root/GameData").get_item(item_id)
	if item == null:
		return ""
	return "%s x%d 줍기" % [item.display_name, count]

func interact(who: Node) -> void:
	var player: Player = who as Player
	if player == null:
		return

	# 넷 스택이 있으면 획득 판정·복제는 호스트 권위 경로로 간다 (설계서 7.2).
	var net: NetPickup = _find_net_pickup()
	if net != null:
		net.request(self, player)
		return
	apply_pickup(player)

## 로컬 적용 (넷 스택이 없는 씬의 즉시 획득 + 호스트 권위 판정의 실행부).
## 실제로 들어간 개수를 반환한다.
func apply_pickup(player: Player) -> int:
	var added: int = player.inventory.add_item(item_id, count)
	if added <= 0:
		return 0

	_clear_floor_smell_source()
	count -= added
	if _event_bus != null:
		_noise_emitter.emit_profile(_event_bus, PICKUP_NOISE, global_position, player)
		_event_bus.item_picked_up.emit(item_id, player)

	if count <= 0:
		deplete()
	return added

## 냄새 나는 바닥 먹이를 청소동물이 한 개 먹는다. 인벤토리나 획득 이벤트를
## 거치지 않는 자원 경쟁 소비이며, 권위가 없는 복제본은 월드 상태를 바꾸지 못한다.
func consume_one_by_scavenger() -> bool:
	if not is_multiplayer_authority() or count <= 0:
		return false
	var item: ItemData = get_node("/root/GameData").get_item(item_id)
	if item == null or not item.is_smell_source():
		return false
	count -= 1
	if count <= 0:
		deplete()
	return true

func _clear_floor_smell_source() -> void:
	if _floor_smell_source == null:
		return
	_floor_smell_source.deactivate()
	_floor_smell_source.queue_free()
	_floor_smell_source = null

func _restore_floor_smell_source() -> void:
	if _floor_smell_source != null:
		return
	var item: ItemData = get_node("/root/GameData").get_item(item_id)
	if item == null or not item.is_smell_source():
		return
	_floor_smell_source = SmellSource.new()
	_floor_smell_source.kind = item.get_smell_kind()
	_floor_smell_source.strength = item.smell_strength
	_floor_smell_source.interval_seconds = item.smell_interval_seconds
	add_child(_floor_smell_source)

## 같은 기계(멀티플레이 브랜치)의 NetPickup 만 잡는다 — 헤드리스 하네스에선
## 한 트리에 기계가 2개다. 상호작용 시점에만 1회 조회하고 캐시한다 (성능문서 6.1).
func _find_net_pickup() -> NetPickup:
	if _net_pickup_cached:
		return _net_pickup
	_net_pickup_cached = true
	for node: Node in get_tree().get_nodes_in_group(&"net_pickup"):
		if (node as NetPickup).owns(self):
			_net_pickup = node as NetPickup
			break
	return _net_pickup

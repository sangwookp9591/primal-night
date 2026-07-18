class_name CampfireSite
extends Area2D

## 모닥불을 놓을 수 있는 지정 자리. 자유 건축이 아니라 여기에만 스냅된다 (설계서 5.8).
## 돌 + 나무를 소비해 설치·점화한다.

const CampfireScene: PackedScene = preload("res://scenes/props/campfire.tscn")
const DEFAULT_CONFIG: CampfireConfig = preload("res://data/props/campfire_config.tres")
const BUILD_NOISE: NoiseProfile = preload("res://data/senses/noise_campfire_build.tres")
const STATE_SHEET: Texture2D = preload("res://assets/sprites/props/campfire_states_sheet.png")
const COOK_SECONDS: float = 3.0

@export var config: CampfireConfig = DEFAULT_CONFIG

var campfire: Campfire = null
var _game_data: Node = null
var _event_bus: Node = null
var _noise_emitter: NoiseEmitter = NoiseEmitter.new()
var _cooking_smell: SmellSource = null

func _ready() -> void:
	var site_sprite := get_node_or_null("SiteSprite") as Sprite2D
	if site_sprite != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = STATE_SHEET
		atlas.region = Rect2(Vector2.ZERO, Vector2(128.0, 128.0))
		site_sprite.texture = atlas
	_game_data = get_node("/root/GameData")
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")

func can_interact(who: Node) -> bool:
	if campfire != null:
		var cook := who as Player
		return campfire.is_lit and cook != null and cook.inventory.has_item(&"raw_meat", 1)

	var player: Player = who as Player
	if player == null:
		return false

	return player.inventory.has_item(&"stone", config.stone_cost) \
		and player.inventory.has_item(&"wood", config.wood_cost)

func get_hold_seconds() -> float:
	return COOK_SECONDS if campfire != null else config.build_seconds

func get_prompt() -> String:
	if campfire != null:
		return "고기 굽기"
	# 표시 문구와 수치는 데이터에서 만든다 (설계서 5.6: UI 하드코딩 금지).
	var stone: ItemData = _game_data.get_item(&"stone")
	var wood: ItemData = _game_data.get_item(&"wood")
	if stone == null or wood == null:
		return ""
	return "모닥불 설치 (%s x%d, %s x%d)" % [
		stone.display_name, config.stone_cost,
		wood.display_name, config.wood_cost,
	]

func interact(who: Node) -> void:
	if not can_interact(who):
		return

	var player: Player = who as Player
	if campfire != null:
		var cook_net := _find_net_campfire()
		if cook_net != null:
			cook_net.request_cook(self, player)
		else:
			apply_cook(player)
		return
	# 넷 스택이 있으면 설치 판정·복제는 호스트 권위 경로로 간다 (설계서 7.2, W2-T5).
	var net: NetCampfire = _find_net_campfire()
	if net != null:
		net.request(self, player)
		return
	if not consume_materials(player):
		return
	build_and_light()


func on_hold_started(who: Node) -> void:
	if campfire == null:
		return
	var player := who as Player
	if player == null:
		return
	_start_cooking_smell()
	var net := _find_net_campfire()
	if net != null:
		net.notify_cook_hold_started(self, player)


func on_hold_ended(who: Node) -> void:
	if campfire == null:
		return
	_end_cooking_smell()
	var player := who as Player
	var net := _find_net_campfire()
	if net != null and player != null:
		net.notify_cook_hold_ended(self, player)


## 날고기 1 → 구운 고기 1의 전부 아니면 전무 변환.
func apply_cook(player: Player) -> bool:
	if player == null or campfire == null or not campfire.is_lit:
		return false
	if not player.inventory.remove_item(&"raw_meat", 1):
		return false
	if player.inventory.add_item(&"cooked_meat", 1) != 1:
		player.inventory.add_item(&"raw_meat", 1)
		return false
	return true


func _start_cooking_smell() -> void:
	if _cooking_smell != null or not multiplayer.is_server():
		return
	var cooked: ItemData = _game_data.get_item(&"cooked_meat")
	if cooked == null:
		return
	_cooking_smell = SmellSource.new()
	_cooking_smell.name = "CookingSmell"
	_cooking_smell.kind = cooked.get_smell_kind()
	_cooking_smell.strength = cooked.smell_strength
	_cooking_smell.interval_seconds = cooked.smell_interval_seconds
	add_child(_cooking_smell)


func _end_cooking_smell() -> void:
	if _cooking_smell == null:
		return
	_cooking_smell.deactivate()
	_cooking_smell.queue_free()
	_cooking_smell = null


func has_cooking_smell() -> bool:
	return _cooking_smell != null

## 재료 소비 (전부 아니면 전무). 하나만 빠지고 실패하면 재료가 증발하므로 되돌린다.
## 넷 스택이 없는 로컬 설치와 호스트 권위 판정·클라이언트 복제 적용이 공유한다.
func consume_materials(player: Player) -> bool:
	if not player.inventory.remove_item(&"stone", config.stone_cost):
		return false
	if not player.inventory.remove_item(&"wood", config.wood_cost):
		player.inventory.add_item(&"stone", config.stone_cost)
		return false
	return true

## 설치·점화 실행부. 이벤트 발신 여부는 Campfire 가 권위 기준으로 판단한다.
func build_and_light() -> void:
	campfire = CampfireScene.instantiate()
	campfire.config = config
	# 자유 건축 금지: 플레이어 위치가 아니라 이 자리에 스냅한다.
	campfire.global_position = global_position
	get_parent().add_child(campfire)
	_noise_emitter.emit_profile(_event_bus, BUILD_NOISE, global_position, self)
	campfire.light()

## 같은 기계(멀티플레이 브랜치)의 NetCampfire 만 잡는다 — 헤드리스 하네스에선
## 한 트리에 기계가 2개다. 설치 홀드 완료 시점에만 불리는 저빈도 조회라 캐시하지 않는다.
func _find_net_campfire() -> NetCampfire:
	for node: Node in get_tree().get_nodes_in_group(&"net_campfire"):
		if (node as NetCampfire).owns(self):
			return node as NetCampfire
	return null

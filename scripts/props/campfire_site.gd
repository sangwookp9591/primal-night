class_name CampfireSite
extends Area2D

## 모닥불을 놓을 수 있는 지정 자리. 자유 건축이 아니라 여기에만 스냅된다 (설계서 5.8).
## 돌 + 나무를 소비해 설치·점화한다.

const CampfireScene: PackedScene = preload("res://scenes/props/campfire.tscn")
const DEFAULT_CONFIG: CampfireConfig = preload("res://data/props/campfire_config.tres")

@export var config: CampfireConfig = DEFAULT_CONFIG

var campfire: Campfire = null
var _game_data: Node = null

func _ready() -> void:
	_game_data = get_node("/root/GameData")

func can_interact(who: Node) -> bool:
	if campfire != null:
		return false

	var player: Player = who as Player
	if player == null:
		return false

	return player.inventory.has_item(&"stone", config.stone_cost) \
		and player.inventory.has_item(&"wood", config.wood_cost)

func get_hold_seconds() -> float:
	return config.build_seconds

func get_prompt() -> String:
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
	# 넷 스택이 있으면 설치 판정·복제는 호스트 권위 경로로 간다 (설계서 7.2, W2-T5).
	var net: NetCampfire = _find_net_campfire()
	if net != null:
		net.request(self, player)
		return
	if not consume_materials(player):
		return
	build_and_light()

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
	campfire.light()

## 같은 기계(멀티플레이 브랜치)의 NetCampfire 만 잡는다 — 헤드리스 하네스에선
## 한 트리에 기계가 2개다. 설치 홀드 완료 시점에만 불리는 저빈도 조회라 캐시하지 않는다.
func _find_net_campfire() -> NetCampfire:
	for node: Node in get_tree().get_nodes_in_group(&"net_campfire"):
		if (node as NetCampfire).owns(self):
			return node as NetCampfire
	return null

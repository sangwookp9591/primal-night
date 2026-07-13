class_name CampfireSite
extends Area2D

## 모닥불을 놓을 수 있는 지정 자리. 자유 건축이 아니라 여기에만 스냅된다 (설계서 5.8).
## 돌 + 나무를 소비해 설치·점화한다.

const CampfireScene: PackedScene = preload("res://scenes/props/campfire.tscn")
const DEFAULT_CONFIG: CampfireConfig = preload("res://data/props/campfire_config.tres")

@export var config: CampfireConfig = DEFAULT_CONFIG

var campfire: Campfire = null

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
	var game_data: Node = get_node("/root/GameData")
	var stone: ItemData = game_data.get_item(&"stone")
	var wood: ItemData = game_data.get_item(&"wood")
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
	# 재료를 모두 뺄 수 있을 때만 짓는다. 하나만 빠지고 실패하면 재료가 증발한다.
	if not player.inventory.remove_item(&"stone", config.stone_cost):
		return
	if not player.inventory.remove_item(&"wood", config.wood_cost):
		player.inventory.add_item(&"stone", config.stone_cost)
		return

	campfire = CampfireScene.instantiate()
	campfire.config = config
	# 자유 건축 금지: 플레이어 위치가 아니라 이 자리에 스냅한다.
	campfire.global_position = global_position
	get_parent().add_child(campfire)
	campfire.light()

class_name HealTarget
extends Area2D

## 출혈 중인 플레이어를 붕대로 지혈하는 상호작용 지점 (설계서 5.2).
## 동료가 길게 눌러 치료하며, 치료 중에는 양쪽 모두 이동이 제한된다.
## 자기 자신에게도 같은 경로로 붕대를 쓸 수 있다 (혼자 플레이).
##
## 네트워크 동기화는 2주차 태스크다. 지금은 로컬 기준으로만 동작한다.

const BANDAGE_ID: StringName = &"bandage"

var _player: Player = null

func _ready() -> void:
	_player = get_parent() as Player

func can_interact(who: Node) -> bool:
	if _player == null or not _player.health.is_bleeding:
		return false
	var healer: Player = who as Player
	if healer == null:
		return false
	return healer.inventory.has_item(BANDAGE_ID, 1)

func get_hold_seconds() -> float:
	return _player.health.config.bandage_hold_seconds

func get_prompt() -> String:
	# 표시 문구도 데이터에서 만든다 (설계서 5.6: UI 하드코딩 금지).
	var bandage: ItemData = get_node("/root/GameData").get_item(BANDAGE_ID)
	if bandage == null:
		return ""
	return "%s 사용" % bandage.display_name

func on_hold_started(_who: Node) -> void:
	# 치료받는 쪽도 이동이 제한된다. 치료하는 쪽은 Interactor 가 잠근다.
	_player.movement_locked = true

func on_hold_ended(_who: Node) -> void:
	_player.movement_locked = false

func interact(who: Node) -> void:
	if not can_interact(who):
		return

	var healer: Player = who as Player
	if not healer.inventory.remove_item(BANDAGE_ID, 1):
		return

	_player.health.stop_bleeding()

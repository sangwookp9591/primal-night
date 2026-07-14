class_name HealTarget
extends Area2D

## 출혈 중인 플레이어를 붕대로 지혈하는 상호작용 지점 (설계서 5.2).
## 동료가 길게 눌러 치료하며, 치료 중에는 양쪽 모두 이동이 제한된다.
## 자기 자신에게도 같은 경로로 붕대를 쓸 수 있다 (혼자 플레이).
##
## 네트워크 동기화는 2주차 태스크다. 지금은 로컬 기준으로만 동작한다.

const BANDAGE_ID: StringName = &"bandage"

var _player: Player = null
var _game_data: Node = null
var _net_survival: NetSurvival = null
var _net_survival_cached: bool = false

func _ready() -> void:
	_player = get_parent() as Player
	_game_data = get_node("/root/GameData")

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
	var bandage: ItemData = _game_data.get_item(BANDAGE_ID)
	if bandage == null:
		return ""
	return "%s 사용" % bandage.display_name

func on_hold_started(who: Node) -> void:
	# 치료받는 쪽도 이동이 제한된다. 치료하는 쪽은 Interactor 가 잠근다.
	_player.movement_locked = true
	var net: NetSurvival = _find_net_survival()
	if net != null:
		# 호스트가 세션을 열고 원격 환자의 기계에도 잠금을 복제한다 (설계서 5.2).
		net.notify_heal_hold_started(who as Player, _player)

func on_hold_ended(who: Node) -> void:
	_player.movement_locked = false
	var net: NetSurvival = _find_net_survival()
	if net != null:
		# 커밋이 먼저 처리된 뒤라면(치료 완료) 호스트에서 no-op 이다.
		net.notify_heal_hold_ended(who as Player)

func interact(who: Node) -> void:
	if not can_interact(who):
		return

	var healer: Player = who as Player
	var net: NetSurvival = _find_net_survival()
	if net != null:
		# 검증·확정은 호스트 권위 (설계서 7.2). 클라이언트 상태는 복제로 맞춰진다.
		net.request_heal_commit_for(healer, _player)
		return
	if not healer.inventory.remove_item(BANDAGE_ID, 1):
		return

	_player.health.stop_bleeding()

## 같은 기계(멀티플레이 브랜치)의 NetSurvival 만 잡는다. 상호작용 시점 1회 조회 후 캐시.
func _find_net_survival() -> NetSurvival:
	if _net_survival_cached:
		return _net_survival
	_net_survival_cached = true
	for node: Node in get_tree().get_nodes_in_group(&"net_survival"):
		if (node as NetSurvival).owns(self):
			_net_survival = node as NetSurvival
			break
	return _net_survival

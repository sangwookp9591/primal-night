class_name DebugHurt
extends Node

## 디버그용 부상 수단. 목표 장면("한 명이 다쳐 피 냄새가 발생한다")을 손으로 재현한다.
## debug_hurt 키(H)를 누르면 자기 캐릭터가 다치고 출혈이 시작된다.
## 넷 스택이 있으면 피해 판정은 호스트 권위 경로(NetSurvival)로 간다 (설계서 7.2).
## ponytail: 릴리스 빌드에서는 이 노드를 씬에서 빼면 된다.

@export var damage: float = 25.0

var _net_survival: NetSurvival = null
var _net_survival_cached: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hurt"):
		hurt(_local_player())

func hurt(player: Player) -> void:
	if player == null or not player.health.is_alive():
		return

	var net: NetSurvival = _find_net_survival()
	if net != null:
		net.request_hurt_for(player, damage)
		return
	player.health.take_damage(damage, &"debug")
	player.health.start_bleeding()

## 이 기계가 조종하는 아바타 — H 키는 자기 캐릭터만 다치게 한다.
func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var player: Player = node as Player
		if player != null and player.multiplayer == multiplayer \
				and player.controller_peer_id == multiplayer.get_unique_id():
			return player
	return null

## 같은 기계(멀티플레이 브랜치)의 NetSurvival 만 잡는다. 부상 시점에만 1회 조회 후 캐시.
func _find_net_survival() -> NetSurvival:
	if _net_survival_cached:
		return _net_survival
	_net_survival_cached = true
	for node: Node in get_tree().get_nodes_in_group(&"net_survival"):
		if (node as NetSurvival).owns(self):
			_net_survival = node as NetSurvival
			break
	return _net_survival

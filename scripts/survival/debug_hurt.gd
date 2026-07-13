class_name DebugHurt
extends Node

## 디버그용 부상 수단. 목표 장면("한 명이 다쳐 피 냄새가 발생한다")을 손으로 재현한다.
## debug_hurt 키(H)를 누르면 플레이어가 다치고 출혈이 시작된다.
## ponytail: 릴리스 빌드에서는 이 노드를 씬에서 빼면 된다.

@export var damage: float = 25.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hurt"):
		hurt(get_tree().get_first_node_in_group("player") as Player)

func hurt(player: Player) -> void:
	if player == null or not player.health.is_alive():
		return

	player.health.take_damage(damage, &"debug")
	player.health.start_bleeding()

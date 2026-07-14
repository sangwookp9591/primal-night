class_name StealthZone
extends Area2D

## 수풀 은신 구역 (설계서 5.6). 회색 상자 — Area2D + 사각형이면 충분하다.
## 판정(소리 반경·프로필 선택)은 Player 가 갖는다. 여기서는 겹침만 알린다.

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body is Player:
		(body as Player).in_bush = true

func _on_body_exited(body: Node) -> void:
	if body is Player:
		(body as Player).in_bush = false

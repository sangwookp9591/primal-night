class_name BloodTrail
extends Node2D

## 출혈 이동의 순수 시각 피드백. 냄새/AI 이벤트는 발신하지 않는다.
const DROP_INTERVAL_SECONDS: float = 0.28
const DROP_LIFETIME_SECONDS: float = 4.0
const MIN_MOVE_DISTANCE: float = 10.0

var player: Player
var drops: Array[Dictionary] = []
var _elapsed: float = 0.0
var _last_drop_position: Vector2 = Vector2.INF


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = -1


func _process(delta: float) -> void:
	for index: int in range(drops.size() - 1, -1, -1):
		drops[index].remaining = float(drops[index].remaining) - delta
		if drops[index].remaining <= 0.0:
			drops.remove_at(index)
	if player != null and player.health.is_bleeding and not player.velocity.is_zero_approx():
		_elapsed += delta
		if _elapsed >= DROP_INTERVAL_SECONDS and (_last_drop_position == Vector2.INF \
				or player.global_position.distance_to(_last_drop_position) >= MIN_MOVE_DISTANCE):
			_elapsed = 0.0
			_last_drop_position = player.global_position
			drops.append({position = player.global_position, remaining = DROP_LIFETIME_SECONDS})
	queue_redraw()


func _draw() -> void:
	for drop: Dictionary in drops:
		var alpha: float = clampf(float(drop.remaining) / DROP_LIFETIME_SECONDS, 0.0, 1.0)
		draw_circle(drop.position, 4.0, Color(0.35, 0.025, 0.02, alpha * 0.72))

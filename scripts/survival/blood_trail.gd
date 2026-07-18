class_name BloodTrail
extends Node2D

## 출혈 이동이 남긴 피 웅덩이. 시각 흔적이자 짧은 냄새 원천이며,
## 플레이어가 3초를 지불해 흙으로 덮을 수 있다.
const DROP_INTERVAL_SECONDS: float = 0.28
const DROP_LIFETIME_SECONDS: float = 6.0
const MIN_MOVE_DISTANCE: float = 10.0
const DROP_SMELL_STRENGTH: float = 18.0
const CLEARED_SMELL_RATIO: float = 0.1

class BloodDrop extends Area2D:
	var trail: BloodTrail
	var remaining: float = DROP_LIFETIME_SECONDS
	var smell_source: SmellSource
	var cleared: bool = false

	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		monitoring = false
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		shape.shape = circle
		add_child(shape)
		smell_source = SmellSource.new()
		smell_source.kind = &"blood"
		smell_source.strength = DROP_SMELL_STRENGTH
		smell_source.interval_seconds = 0.5
		add_child(smell_source)

	func can_interact(who: Node) -> bool:
		return not cleared and who is Player

	func get_hold_seconds() -> float:
		return 3.0

	func get_prompt() -> String:
		return "피 흔적 덮기"

	func interact(who: Node) -> void:
		var player := who as Player
		if player == null or cleared:
			return
		if multiplayer.is_server():
			apply_clear(player)
		else:
			request_clear.rpc_id(1, String(player.name))

	@rpc("any_peer", "call_remote", "reliable")
	func request_clear(player_name: String) -> void:
		if not multiplayer.is_server():
			return
		var player := get_tree().get_first_node_in_group(&"player") as Player
		for candidate: Node in get_tree().get_nodes_in_group(&"player"):
			if candidate.name == player_name and candidate.multiplayer == multiplayer:
				player = candidate as Player
				break
		if player != null and player.global_position.distance_to(global_position) <= 72.0:
			apply_clear(player)

	func apply_clear(player: Player) -> void:
		if cleared:
			return
		cleared = true
		smell_source.strength = DROP_SMELL_STRENGTH * CLEARED_SMELL_RATIO
		var grid := SmellGrid.find_in(get_tree())
		if grid != null:
			grid.set_registered_smell_strength(smell_source, smell_source.strength)
		trail.add_dirty_hands_smell(player)

	func current_smell_strength() -> float:
		return smell_source.strength

var player: Player
var drops: Array[Dictionary] = []
var _drop_serial: int = 0
var _elapsed: float = 0.0
var _last_drop_position: Vector2 = Vector2.INF


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = -1


func _process(delta: float) -> void:
	for index: int in range(drops.size() - 1, -1, -1):
		var drop := drops[index].node as BloodDrop
		drop.remaining -= delta
		drops[index].remaining = drop.remaining
		if drop.remaining <= 0.0:
			drop.queue_free()
			drops.remove_at(index)
	if player != null and player.health.is_bleeding and not player.velocity.is_zero_approx():
		_elapsed += delta
		if _elapsed >= DROP_INTERVAL_SECONDS and (_last_drop_position == Vector2.INF \
				or player.global_position.distance_to(_last_drop_position) >= MIN_MOVE_DISTANCE):
			_elapsed = 0.0
			_last_drop_position = player.global_position
			var drop := BloodDrop.new()
			drop.name = "BloodDrop_%d" % _drop_serial
			_drop_serial += 1
			drop.trail = self
			drop.position = player.global_position
			add_child(drop)
			drops.append({position = player.global_position,
				remaining = DROP_LIFETIME_SECONDS, node = drop})
	queue_redraw()


func _draw() -> void:
	for drop: Dictionary in drops:
		var alpha: float = clampf(float(drop.remaining) / DROP_LIFETIME_SECONDS, 0.0, 1.0)
		if (drop.node as BloodDrop).cleared:
			alpha *= 0.22
		draw_circle(drop.position, 4.0, Color(0.35, 0.025, 0.02, alpha * 0.72))


func add_dirty_hands_smell(target: Player) -> void:
	if not multiplayer.is_server():
		return
	var prior := target.get_node_or_null("DirtyHandsSmell") as SmellSource
	if prior != null:
		prior.queue_free()
	var source := SmellSource.new()
	source.name = "DirtyHandsSmell"
	source.kind = &"blood"
	source.strength = 24.0
	source.interval_seconds = 0.5
	target.add_child(source)
	var timer := get_tree().create_timer(8.0)
	timer.timeout.connect(_expire_dirty_hands.bind(weakref(source)))


func _expire_dirty_hands(source_ref: WeakRef) -> void:
	var source := source_ref.get_ref() as SmellSource
	if source != null:
		source.deactivate()
		source.queue_free()

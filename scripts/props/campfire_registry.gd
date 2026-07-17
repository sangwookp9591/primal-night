extends Node

## 켜진 모닥불의 단일 소유자. 소비자는 아래 조회 API만 사용하고 목록을 보관하지 않는다.
## 값은 WeakRef 로 노드를 잡아 queue_free 순서와 무관하게 유령 항목을 정리한다.

var _fires_by_id: Dictionary = {}


func register_fire(campfire: Node, position: Vector2, radius: float) -> void:
	if not is_instance_valid(campfire) or not position.is_finite() \
			or not is_finite(radius) or radius <= 0.0:
		return
	var instance_id: int = campfire.get_instance_id()
	_fires_by_id[instance_id] = {
		node_ref = weakref(campfire),
		position = position,
		radius = radius,
	}
	var on_tree_exiting := _on_fire_tree_exiting.bind(instance_id)
	if not campfire.tree_exiting.is_connected(on_tree_exiting):
		campfire.tree_exiting.connect(on_tree_exiting, CONNECT_ONE_SHOT)


func unregister_fire(campfire: Variant) -> void:
	_prune_invalid()
	if is_instance_valid(campfire) and campfire is Node:
		_fires_by_id.erase((campfire as Node).get_instance_id())


## 현재 살아 있는 불의 읽기 전용 스냅샷 [{node, position, radius}].
func get_active_fires() -> Array[Dictionary]:
	_prune_invalid()
	var active: Array[Dictionary] = []
	for entry: Dictionary in _fires_by_id.values():
		var node: Node = entry.node_ref.get_ref() as Node
		active.append({
			node = node,
			position = entry.position,
			radius = entry.radius,
		})
	return active


## 위치에서 가장 가까운 불. 없으면 빈 Dictionary.
func nearest_fire(position: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance_squared: float = INF
	for fire: Dictionary in get_active_fires():
		var distance_squared: float = position.distance_squared_to(fire.position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			nearest = fire
	return nearest


func is_position_protected(position: Vector2, radius_ratio: float = 1.0) -> bool:
	return not nearest_fire_containing(position, radius_ratio).is_empty()


## 반경 * ratio 안에 있는 불 중 가장 가까운 항목. 없으면 빈 Dictionary.
func nearest_fire_containing(position: Vector2, radius_ratio: float = 1.0) -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance_squared: float = INF
	for fire: Dictionary in get_active_fires():
		var distance_squared: float = position.distance_squared_to(fire.position)
		var effective_radius: float = fire.radius * radius_ratio
		if distance_squared <= effective_radius * effective_radius \
				and distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			nearest = fire
	return nearest


func clear_for_test() -> void:
	_fires_by_id.clear()


func _on_fire_tree_exiting(instance_id: int) -> void:
	_fires_by_id.erase(instance_id)


func _prune_invalid() -> void:
	for instance_id: int in _fires_by_id.keys():
		var node_ref: WeakRef = _fires_by_id[instance_id].node_ref
		if node_ref.get_ref() == null:
			_fires_by_id.erase(instance_id)

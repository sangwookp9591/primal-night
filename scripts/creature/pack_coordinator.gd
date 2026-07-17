class_name PackCoordinator
extends Node

## 랩터 무리 조율. 실시간 플레이어 좌표를 추적하지 않고, 랩터가 이미 확정한
## 단서 좌표나 현재 보이는 후보 목록만 받아 역할을 나눈다.

@export var flank_distance: float = 96.0
@export var max_coordinated_raptors: int = 4


func _ready() -> void:
	add_to_group(&"raptor_pack_coordinator")


func assign_investigation_target(raptor: Raptor, cue_position: Vector2) -> Vector2:
	var members: Array[Raptor] = _pack_members_for(raptor)
	if members.size() <= 1:
		return cue_position
	var index: int = mini(members.find(raptor), max_coordinated_raptors - 1)
	if index < 0:
		return cue_position
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var ring: float = 1.0 + float(index / 2) * 0.5
	var approach: Vector2 = cue_position - raptor.global_position
	if approach.is_zero_approx():
		approach = Vector2.RIGHT
	var lateral: Vector2 = approach.normalized().orthogonal() * side
	return cue_position + lateral * flank_distance * ring


func choose_visible_target(raptor: Raptor, candidates: Array[Node2D]) -> Node2D:
	if candidates.is_empty():
		return null
	if _pack_members_for(raptor).size() <= 1:
		return _nearest_to(raptor.global_position, candidates)
	var best: Node2D = null
	var best_isolation: float = -1.0
	var best_distance: float = INF
	for candidate: Node2D in candidates:
		var isolation: float = _nearest_neighbor_distance(candidate, candidates)
		var distance: float = raptor.global_position.distance_to(candidate.global_position)
		if isolation > best_isolation or (is_equal_approx(isolation, best_isolation)
				and distance < best_distance):
			best = candidate
			best_isolation = isolation
			best_distance = distance
	return best


func _pack_members_for(raptor: Raptor) -> Array[Raptor]:
	var members: Array[Raptor] = []
	if raptor == null:
		return members
	for node: Node in get_tree().get_nodes_in_group(&"raptor"):
		var peer := node as Raptor
		if peer == null or peer.multiplayer != raptor.multiplayer:
			continue
		members.append(peer)
	members.sort_custom(func(a: Raptor, b: Raptor) -> bool:
		return a.get_instance_id() < b.get_instance_id())
	if members.size() > max_coordinated_raptors:
		members.resize(max_coordinated_raptors)
	return members


func _nearest_to(position: Vector2, candidates: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for candidate: Node2D in candidates:
		var distance: float = position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _nearest_neighbor_distance(candidate: Node2D, candidates: Array[Node2D]) -> float:
	var nearest: float = INF
	for other: Node2D in candidates:
		if other == candidate:
			continue
		nearest = minf(nearest, candidate.global_position.distance_to(other.global_position))
	return nearest

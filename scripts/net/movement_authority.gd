class_name MovementAuthority
extends RefCounted

## 호스트 이동 검증 골격 (설계서 7.2/7.4).
## 클라이언트가 보낸 좌표를 그대로 신뢰하지 않는다 — 직전 권위 위치 대비
## 최대 이동거리(텔레포트 검사)를 넘으면 거부하고 직전 위치를 유지한다.
## 이동 예산: max_speed * elapsed * tolerance, 최소 min_allowance_px.
## 벽 통과 등 경로 검증은 이 주 범위가 아니다 — 거리 검증만 한다.

var _tolerance: float
var _min_allowance_px: float
var _positions: Dictionary = {}
var _violations: Dictionary = {}


func _init(tolerance: float, min_allowance_px: float) -> void:
	_tolerance = tolerance
	_min_allowance_px = min_allowance_px


func register_player(player_id: StringName, position: Vector2) -> void:
	_positions[player_id] = position
	_violations[player_id] = 0


func unregister_player(player_id: StringName) -> void:
	_positions.erase(player_id)
	_violations.erase(player_id)


func has_player(player_id: StringName) -> bool:
	return _positions.has(player_id)


## 클라이언트가 주장한 위치를 검증하고 확정 위치를 돌려준다.
## 위반이면 직전 위치를 유지하고 위반 횟수를 올린다. 호출자는 등록을 보장한다.
func submit(player_id: StringName, claimed_position: Vector2, elapsed_seconds: float, max_speed: float) -> Vector2:
	if not _positions.has(player_id):
		push_warning("MovementAuthority: 미등록 플레이어 %s 의 이동 제출을 거부" % player_id)
		return Vector2.ZERO

	var last_position: Vector2 = _positions[player_id]
	if not claimed_position.is_finite():
		return _reject(player_id, last_position)

	var max_distance: float = maxf(max_speed * elapsed_seconds * _tolerance, _min_allowance_px)
	if last_position.distance_to(claimed_position) > max_distance:
		return _reject(player_id, last_position)

	_positions[player_id] = claimed_position
	return claimed_position


func get_position(player_id: StringName) -> Vector2:
	return _positions.get(player_id, Vector2.ZERO)


func get_violation_count(player_id: StringName) -> int:
	return _violations.get(player_id, 0)


func _reject(player_id: StringName, last_position: Vector2) -> Vector2:
	_violations[player_id] = int(_violations[player_id]) + 1
	return last_position

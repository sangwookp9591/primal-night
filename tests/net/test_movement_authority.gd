extends GutTest

## MovementAuthority — 호스트 텔레포트 검증 (설계서 7.4: 좌표를 그대로 신뢰하지 않음).
## 검증 예산: max_speed * elapsed * tolerance, 최소 min_allowance_px 보장.

const TOLERANCE: float = 1.25
const MIN_ALLOWANCE_PX: float = 8.0
const MAX_SPEED: float = 240.0

var authority: MovementAuthority


func before_each() -> void:
	authority = MovementAuthority.new(TOLERANCE, MIN_ALLOWANCE_PX)
	authority.register_player(&"p1", Vector2.ZERO)


func test_register_and_unregister_are_observable() -> void:
	assert_true(authority.has_player(&"p1"))
	authority.unregister_player(&"p1")
	assert_false(authority.has_player(&"p1"))


func test_accepts_move_within_speed_budget() -> void:
	var accepted: Vector2 = authority.submit(&"p1", Vector2(100.0, 0.0), 1.0, MAX_SPEED)
	assert_eq(accepted, Vector2(100.0, 0.0))
	assert_eq(authority.get_position(&"p1"), Vector2(100.0, 0.0))
	assert_eq(authority.get_violation_count(&"p1"), 0)


func test_rejects_teleport_and_keeps_last_position() -> void:
	# 240 * 0.1 * 1.25 = 30px 예산인데 1000px 를 주장 → 거부.
	var accepted: Vector2 = authority.submit(&"p1", Vector2(1000.0, 0.0), 0.1, MAX_SPEED)
	assert_eq(accepted, Vector2.ZERO)
	assert_eq(authority.get_position(&"p1"), Vector2.ZERO)
	assert_eq(authority.get_violation_count(&"p1"), 1)


func test_boundary_exactly_at_limit_passes() -> void:
	var accepted: Vector2 = authority.submit(&"p1", Vector2(30.0, 0.0), 0.1, MAX_SPEED)
	assert_eq(accepted, Vector2(30.0, 0.0))
	assert_eq(authority.get_violation_count(&"p1"), 0)


func test_min_allowance_floor_allows_small_move_with_zero_elapsed() -> void:
	var accepted: Vector2 = authority.submit(&"p1", Vector2(5.0, 0.0), 0.0, MAX_SPEED)
	assert_eq(accepted, Vector2(5.0, 0.0))
	assert_eq(authority.get_violation_count(&"p1"), 0)


func test_rejects_non_finite_coordinates() -> void:
	# 임의 페이로드 방어 (설계서 7.4): NaN/INF 좌표는 스키마 위반이다.
	var accepted: Vector2 = authority.submit(&"p1", Vector2(INF, 0.0), 1.0, MAX_SPEED)
	assert_eq(accepted, Vector2.ZERO)
	assert_eq(authority.get_violation_count(&"p1"), 1)


func test_next_valid_move_after_rejection_starts_from_last_position() -> void:
	authority.submit(&"p1", Vector2(1000.0, 0.0), 0.1, MAX_SPEED)
	var accepted: Vector2 = authority.submit(&"p1", Vector2(20.0, 0.0), 0.1, MAX_SPEED)
	assert_eq(accepted, Vector2(20.0, 0.0))
	assert_eq(authority.get_violation_count(&"p1"), 1)

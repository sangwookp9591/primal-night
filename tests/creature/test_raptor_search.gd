extends GutTest

## 랩터 조사 품질: 상실 / 재탐색 / 관심도 (설계서 5.5·14.1, 계획서 W3-T6).
## - 조사 지점에 도착해도 즉시 배회로 돌아가지 않는다. 주변을 N회 짧게 훑은 뒤 상실한다.
## - 더 강한 새 단서(소리·냄새)가 오면 목표를 갈아타고 훑기 횟수를 되돌린다 (재탐색).
## - 더 약한 단서는 지금 쫓는 단서를 흔들지 못한다 (관심도).
## ★ 공정성 규칙 (설계서 5.3, W1 뮤테이션 M3): 훑는 동안에도 발신자 노드를 추적하지 않고
##   플레이어 실시간 좌표를 목표로 덮어쓰지 않는다. 훑기 목표는 오직 조사 원점 + rng 다.

const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")

const SEARCH_SWEEPS: int = 2
const SEARCH_RADIUS: float = 96.0

var _event_bus: Node = null


func before_each() -> void:
	_event_bus = get_node("/root/EventBus")


func _make_data() -> CreatureData:
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 50.0
	data.lose_sight_radius = 80.0
	data.smell_threshold = 8.0
	data.investigate_arrive_distance = 24.0
	data.occlusion_attenuation = 0.5
	data.search_sweeps = SEARCH_SWEEPS
	data.search_radius = SEARCH_RADIUS
	return data


func _spawn_raptor(at: Vector2) -> Raptor:
	var raptor: Raptor = RaptorScript.new()
	raptor.data = _make_data()
	raptor.position = at
	add_child_autofree(raptor)
	raptor.rng.seed = 12345
	return raptor


func _spawn_player(at: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	player.position = at
	add_child_autofree(player)
	return player


func _spawn_smell_grid() -> SmellGrid:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2(-500.0, -500.0)
	grid.area_size = Vector2(1000.0, 1000.0)
	add_child_autofree(grid)
	return grid


## 소리로 조사에 진입시키고, 랩터를 그 지점에 데려다 놓는다 (도착 상태).
func _investigate_noise_at(raptor: Raptor, noise_position: Vector2, radius: float) -> void:
	_event_bus.noise_emitted.emit(noise_position, radius, null)
	await wait_physics_frames(2)
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "전제: 소리로 조사에 진입한다")
	assert_eq(raptor.move_target, noise_position, "전제: 목표는 들린 위치다")
	raptor.global_position = noise_position


## 도착했는데 아무것도 없다 → 즉시 배회가 아니라 주변을 N회 훑고, 그 뒤에야 상실한다.
func test_arrival_sweeps_the_area_n_times_before_losing_interest() -> void:
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	var noise_position: Vector2 = Vector2(300.0, 0.0)
	await _investigate_noise_at(raptor, noise_position, 400.0)

	for sweep: int in range(SEARCH_SWEEPS):
		raptor._ai_tick()
		assert_eq(raptor.state, Raptor.State.INVESTIGATE,
			"%d번째 훑기 중에는 조사 상태다 — 도착 즉시 배회로 돌아가지 않는다" % (sweep + 1))
		assert_ne(raptor.move_target, raptor.global_position,
			"훑기는 제자리가 아니라 주변의 새 지점을 본다")
		assert_lte(raptor.move_target.distance_to(noise_position), SEARCH_RADIUS,
			"훑기 목표는 조사 원점 주변이다")
		# 훑기 지점에 도착한다.
		raptor.global_position = raptor.move_target

	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.WANDER,
		"%d회 훑어도 아무것도 없으면 대상을 상실하고 배회로 복귀한다" % SEARCH_SWEEPS)


## ★ 공정성 규칙 (W1 M3): 훑는 동안 플레이어가 시야 밖에서 움직여도
## 훑기 목표는 조사 원점 주변에서만 나온다. 실시간 좌표를 절대 덮어쓰지 않는다.
func test_search_sweeps_never_follow_the_live_player_position() -> void:
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	var noise_position: Vector2 = Vector2(300.0, 0.0)
	var player: Node2D = _spawn_player(Vector2(300.0, 0.0))
	await _investigate_noise_at(raptor, noise_position, 400.0)

	for player_position: Vector2 in [Vector2(-900.0, 500.0), Vector2(700.0, -400.0)]:
		player.position = player_position
		raptor._ai_tick()
		assert_eq(raptor.state, Raptor.State.INVESTIGATE, "훑기 중에는 조사 상태다")
		assert_ne(raptor.move_target, player_position,
			"플레이어의 새 위치 %s 를 목표로 삼으면 안 된다 (좌표 투시 금지)" % player_position)
		assert_lte(raptor.move_target.distance_to(noise_position), SEARCH_RADIUS,
			"훑기 목표는 들었던 위치 주변에서만 나온다")
		raptor.global_position = raptor.move_target


## 관심도: 지금 쫓는 단서보다 약한 소리는 목표를 흔들지 못한다.
## ★ 조용한 소리도 '들리는' 위치에 둔다 — 반경 밖에 두면 청취 단계에서 걸러져
##   관심도 규칙을 검증하지 못한다 (이 테스트가 처음 뮤테이션을 놓쳤던 이유다).
func test_quieter_noise_does_not_override_a_louder_investigation() -> void:
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	var loud_position: Vector2 = Vector2(300.0, 0.0)
	await _investigate_noise_at(raptor, loud_position, 400.0)

	# 랩터(300,0)에서 거리 200, 반경 250 — 들린다. 하지만 세기 250 < 400 이라
	# 지금 쫓는 큰 소리(400)를 밀어내지 못한다.
	var quiet_position: Vector2 = Vector2(100.0, 0.0)
	_event_bus.noise_emitted.emit(quiet_position, 250.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "조사는 유지된다")
	assert_ne(raptor.move_target, quiet_position,
		"더 약한 소리는 관심을 빼앗지 못한다 — 목표를 갈아타면 안 된다")
	assert_lte(raptor.move_target.distance_to(loud_position), SEARCH_RADIUS,
		"원래 조사 지점 주변을 계속 훑는다")


## 재탐색: 더 큰 소리가 오면 목표를 갈아타고 훑기 횟수도 되돌린다.
func test_louder_noise_restarts_the_search_elsewhere() -> void:
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	await _investigate_noise_at(raptor, Vector2(300.0, 0.0), 400.0)
	# 훑기를 한 번 소진한다.
	raptor._ai_tick()

	var louder_position: Vector2 = Vector2(-200.0, 0.0)
	_event_bus.noise_emitted.emit(louder_position, 900.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "더 큰 소리는 새 조사 대상이다")
	assert_eq(raptor.move_target, louder_position, "목표는 새로 들린 위치다")

	# 훑기 횟수가 되돌아왔다 — 새 지점에서 다시 N회 훑는다.
	raptor.global_position = louder_position
	for sweep: int in range(SEARCH_SWEEPS):
		raptor._ai_tick()
		assert_eq(raptor.state, Raptor.State.INVESTIGATE,
			"재탐색은 훑기 횟수를 처음부터 다시 센다 (%d번째)" % (sweep + 1))
		raptor.global_position = raptor.move_target
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.WANDER, "새 지점에서도 다 훑으면 상실한다")


func test_repeated_moving_noise_updates_target_until_emission_stops() -> void:
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	var player: Node2D = _spawn_player(Vector2(200.0, 0.0))

	_event_bus.noise_emitted.emit(player.global_position, 400.0, player)
	await wait_physics_frames(2)
	raptor._ai_tick()
	assert_eq(raptor.move_target, Vector2(200.0, 0.0), "첫 소리 위치를 조사한다")

	player.global_position = Vector2(320.0, 0.0)
	_event_bus.noise_emitted.emit(player.global_position, 400.0, player)
	await wait_physics_frames(2)
	raptor._ai_tick()
	assert_eq(raptor.move_target, Vector2(320.0, 0.0),
		"반복 발신 중에는 최신 청취 위치로 조사 목표가 갱신된다")

	player.global_position = Vector2(460.0, 0.0)
	await wait_physics_frames(2)
	raptor._ai_tick()
	assert_eq(raptor.move_target, Vector2(320.0, 0.0),
		"발신이 멈춘 뒤에는 플레이어가 움직여도 마지막 청취 위치에 고정된다")


## 재탐색: 훑는 동안 더 진한 냄새가 들어오면 그쪽으로 다시 탐색한다 (설계서 5.4).
func test_stronger_smell_restarts_the_search() -> void:
	var grid: SmellGrid = _spawn_smell_grid()
	var raptor: Raptor = _spawn_raptor(Vector2(50.0, 50.0))
	await wait_physics_frames(1)
	# 약한 냄새로 조사 시작 — 랩터 셀(0..100) 10, 동쪽 셀(100..200) 20.
	_event_bus.smell_emitted.emit(Vector2(50.0, 50.0), 10.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(150.0, 50.0), 20.0, &"blood")
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "전제: 냄새로 조사에 진입한다")
	assert_eq(raptor.move_target, Vector2(150.0, 50.0), "전제: 경사 방향 한 셀 전진")

	# 훨씬 진한 냄새가 랩터 셀에 깔린다 — 같은 감각의 더 강한 단서다.
	_event_bus.smell_emitted.emit(Vector2(50.0, 50.0), 200.0, &"blood")
	_event_bus.smell_emitted.emit(Vector2(50.0, 150.0), 400.0, &"blood")
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "조사는 유지된다")
	assert_eq(raptor.move_target, Vector2(50.0, 150.0),
		"더 진한 냄새의 경사 방향으로 재탐색한다 — 정확한 발생 좌표를 받지 않는다")


## 감각 우선순위: 시야가 소리를 이긴다 (설계서 5.5).
func test_sight_beats_noise_even_while_investigating() -> void:
	var raptor: Raptor = _spawn_raptor(Vector2.ZERO)
	await _investigate_noise_at(raptor, Vector2(300.0, 0.0), 400.0)
	raptor.global_position = Vector2.ZERO

	# 시야(50) 안에 플레이어가 들어왔다. 동시에 반대쪽에서 아주 큰 소리가 난다.
	var player: Node2D = _spawn_player(Vector2(30.0, 0.0))
	_event_bus.noise_emitted.emit(Vector2(-400.0, 0.0), 900.0, null)
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.CHASE, "직접 지각한 플레이어가 소리보다 우선이다")
	assert_eq(raptor.move_target, player.global_position, "추격 목표는 실제로 지각한 플레이어다")

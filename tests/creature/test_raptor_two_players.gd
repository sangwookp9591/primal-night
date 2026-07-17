extends GutTest

## 랩터 다중 플레이어 인식 (W2-T5, 설계서 5.5).
## 2인 협동에서 랩터는 '두 플레이어 모두' 를 지각해야 한다:
##   - 시야 안에서 가장 가까운 플레이어를 추격한다 (그룹 첫 노드 고정 금지).
##   - 추격 대상이 불 곁에 도달해도, 비보호 동료가 보이면 그쪽으로 전환한다.
##     ★ 한 명만 보호될 때 물러나면 안 된다 — 둘 다 불 반경 안일 때만 물러난다.
##   - 다른 기계(멀티플레이 브랜치)의 플레이어는 지각하지 않는다 (헤드리스 하네스).

const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")
	get_node("/root/CampfireRegistry").clear_for_test()

func _make_data() -> CreatureData:
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 100.0
	data.lose_sight_radius = 200.0
	data.smell_threshold = 8.0
	data.investigate_arrive_distance = 24.0
	data.occlusion_attenuation = 0.5
	return data

func _spawn_raptor(data: CreatureData, at: Vector2) -> Raptor:
	var raptor: Raptor = RaptorScript.new()
	raptor.data = data
	raptor.position = at
	add_child_autofree(raptor)
	return raptor

func _spawn_player(at: Vector2) -> Node2D:
	var player: Node2D = Node2D.new()
	player.add_to_group(&"player")
	player.position = at
	add_child_autofree(player)
	return player

func test_chases_the_nearest_visible_player_not_the_first_in_group() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	_spawn_player(Vector2(80.0, 0.0))  # 그룹에 먼저 등록되는 먼 플레이어
	var near_player: Node2D = _spawn_player(Vector2(50.0, 0.0))

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.CHASE, "시야 안 플레이어는 추격을 촉발한다")
	assert_eq(raptor.move_target, near_player.global_position,
		"가장 가까운 플레이어를 추격해야 한다 (그룹 첫 노드 고정 금지)")

## ★ 목표 장면의 결말 규칙: 추격 대상이 불 곁에 도달해도 비보호 동료가 보이면
## 그쪽으로 전환하고, '모든' 보이는 플레이어가 보호될 때만 물러난다.
func test_flees_only_when_every_visible_player_is_protected() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var protected_player: Node2D = _spawn_player(Vector2(80.0, 0.0))
	var exposed_player: Node2D = _spawn_player(Vector2(0.0, -90.0))
	raptor._ai_tick()
	assert_eq(raptor.state, Raptor.State.CHASE, "전제: 추격 상태여야 한다")

	# 첫 플레이어 위치에 모닥불이 켜진다 (반경 60) — 그는 보호, 동료는 노출.
	var fire: Node = autofree(Node.new())
	get_node("/root/CampfireRegistry").register_fire(
		fire, protected_player.global_position, 60.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.CHASE,
		"비보호 동료가 보이는 동안에는 물러나면 안 된다 (한 명만 보호 금지)")
	assert_eq(raptor.move_target, exposed_player.global_position,
		"추격 대상을 비보호 동료로 전환해야 한다")

	# 동료도 불 반경 안으로 — 이제 전원 보호, 비로소 물러난다.
	exposed_player.position = Vector2(70.0, 0.0)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.FLEE,
		"두 명 다 불 반경 안이면 랩터가 물러나야 한다 (목표 장면의 결말)")

## 헤드리스 2인 하네스에선 한 트리에 기계(멀티플레이 브랜치)가 2개다.
## 랩터는 자기 기계의 플레이어만 지각해야 한다 (Interactor.find_target 관례).
func test_ignores_players_from_another_machine_branch() -> void:
	var raptor: Raptor = _spawn_raptor(_make_data(), Vector2.ZERO)
	var other_machine: Node = add_child_autofree(Node.new())
	get_tree().set_multiplayer(SceneMultiplayer.new(), other_machine.get_path())
	var foreign_player: Node2D = Node2D.new()
	foreign_player.add_to_group(&"player")
	foreign_player.position = Vector2(80.0, 0.0)
	other_machine.add_child(foreign_player)

	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.WANDER,
		"다른 기계의 플레이어는 지각하지 않는다 (하네스에서 오탐 방지)")
	get_tree().set_multiplayer(null, other_machine.get_path())

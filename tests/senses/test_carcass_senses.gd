extends GutTest

## 해체의 감각 대가 (W5-T3, 정본 §14.4).
##
## 판정 문장의 "피 냄새와 소음" 절반이 여기다. 산출만 있고 대가가 없으면
## 해체는 그냥 상자 열기다.
##   절단 소음: 구간 완료마다 240px, 0.5초 안 반복은 병합
##   피 냄새: 신선 80 / 일부 해체 55 / 골격 0

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")
const SmellGridScript = preload("res://scripts/senses/smell_grid.gd")
const SmellGridConfigScript = preload("res://scripts/senses/smell_grid_config.gd")
const RaptorScript = preload("res://scripts/creature/raptor.gd")
const CreatureDataScript = preload("res://scripts/creature/creature_data.gd")
const BUTCHER_NOISE: NoiseProfile = preload("res://data/senses/noise_butcher.tres")

const STONE_KNIFE: StringName = &"stone_knife"

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _make_grid(authority: int = 1) -> SmellGrid:
	var config: SmellGridConfig = SmellGridConfigScript.new()
	config.cell_size = 100.0
	config.tick_interval = 0.25
	config.decay_factor = 1.0
	config.advect_fraction = 0.0
	config.min_active_value = 0.5
	var grid: SmellGrid = SmellGridScript.new()
	grid.config = config
	grid.area_origin = Vector2.ZERO
	grid.area_size = Vector2(1000.0, 1000.0)
	grid.set_multiplayer_authority(authority)
	add_child_autofree(grid)
	return grid

func _make_carcass(at: Vector2 = Vector2(250.0, 250.0)) -> Carcass:
	var carcass: Carcass = CarcassScene.instantiate()
	carcass.position = at
	return add_child_autofree(carcass)

func _make_butcher(at: Vector2 = Vector2(250.0, 250.0)) -> Player:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.global_position = at
	player.inventory.add_item(STONE_KNIFE, 1)
	return player


# --- 피 냄새 단계 -------------------------------------------------------------

func test_fresh_carcass_registers_the_strongest_blood_smell() -> void:
	var grid: SmellGrid = _make_grid()
	var carcass: Carcass = _make_carcass()
	await wait_physics_frames(1)

	assert_eq(grid.get_registered_smell_source_count(), 1, "신선한 사체는 냄새 원천으로 등록된다")
	assert_almost_eq(grid.get_registered_smell_strength(carcass),
		carcass.profile.fresh_smell_strength, 0.01, "신선 80 (정본 §14.4)")


func test_blood_smell_drops_to_partial_after_the_first_stage() -> void:
	var grid: SmellGrid = _make_grid()
	var carcass: Carcass = _make_carcass()
	var player: Player = _make_butcher()

	assert_true(carcass.apply_stage(player), "1구간 해체")

	assert_almost_eq(grid.get_registered_smell_strength(carcass),
		carcass.profile.partial_smell_strength, 0.01, "일부 해체 55 (정본 §14.4)")


func test_blood_smell_stays_partial_through_the_middle_stages() -> void:
	var grid: SmellGrid = _make_grid()
	var carcass: Carcass = _make_carcass()
	var player: Player = _make_butcher()

	for stage: int in range(carcass.profile.stage_count - 1):
		assert_true(carcass.apply_stage(player), "구간 %d 해체" % stage)
		assert_almost_eq(grid.get_registered_smell_strength(carcass),
			carcass.profile.partial_smell_strength, 0.01,
			"골격 전까지는 일부 해체 강도를 유지한다 (구간 %d)" % stage)


## 골격 0 은 "강도 0 원천"이 아니라 등록 해제다 — 남겨 두면 SmellGrid 가 매 틱
## 훑는 목록만 길어진다 (성능문서 5.2).
func test_skeleton_unregisters_the_smell_source_entirely() -> void:
	var grid: SmellGrid = _make_grid()
	var carcass: Carcass = _make_carcass()
	var player: Player = _make_butcher()

	for stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.apply_stage(player))

	assert_eq(carcass.current_smell_strength(), 0.0, "골격 0 (정본 §14.4)")
	# 개수가 아니라 사체 원천을 본다 — 해체한 플레이어는 날고기를 들게 되어
	# 스스로 냄새 원천으로 등록된다 (Inventory 보유 냄새).
	assert_eq(grid.get_registered_smell_strength(carcass), 0.0, "골격은 원천 목록에서 빠진다")


func test_fresh_carcass_actually_accumulates_smell_in_the_grid() -> void:
	var grid: SmellGrid = _make_grid()
	var carcass: Carcass = _make_carcass()
	await wait_physics_frames(1)

	grid._process(0.5)

	assert_gt(grid.get_smell_at(carcass.global_position), 0.0,
		"신선한 사체 위치에서 실제로 냄새가 쌓여야 한다")


func test_a_fresh_carcass_smells_stronger_than_a_partly_butchered_one() -> void:
	var grid: SmellGrid = _make_grid()
	var fresh: Carcass = _make_carcass(Vector2(150.0, 150.0))
	var partial: Carcass = _make_carcass(Vector2(650.0, 650.0))
	var player: Player = _make_butcher(Vector2(650.0, 650.0))
	await wait_physics_frames(1)
	assert_true(partial.apply_stage(player), "전제: 한쪽만 일부 해체")
	# 해체자가 그 자리에 서 있으면 보유한 날고기 냄새가 섞여 사체 비교가 오염된다.
	player.global_position = Vector2(50.0, 950.0)

	grid._process(0.5)

	assert_gt(grid.get_smell_at(fresh.global_position), grid.get_smell_at(partial.global_position),
		"손대지 않은 사체가 더 진하게 난다")


func test_client_grid_does_not_simulate_carcass_smell() -> void:
	# 호스트 권위: 클라이언트 격자는 등록 원천을 자체 시뮬레이션하지 않는다 (정본 §15.5).
	var grid: SmellGrid = _make_grid(2)
	var carcass: Carcass = _make_carcass()

	grid._process(0.5)

	assert_eq(grid.get_smell_at(carcass.global_position), 0.0,
		"클라이언트는 사체 냄새를 스스로 만들지 않는다")


## 실기 경로 회귀 (계측으로 발견): main.tscn 은 SurvivalDemo 를 SmellGrid **앞**에 둔다.
## 사체의 _ready 가 먼저 돌아 그 시점엔 smell_grid 그룹이 비어 있으므로, _ready 에서
## 곧장 등록하면 신선한 사체가 실기에서 무취가 된다 — 이 마일스톤의 위험 절반이
## 조용히 죽는다. 테스트가 격자를 먼저 만들면 절대 재현되지 않는 순서 버그다.
##
## 여기서 사체를 먼저 만드는 순서가 곧 main.tscn 의 순서다 (씬 계약은
## tests/world/test_butcher_scene_contract.gd 가 실제 씬으로도 지킨다).
func test_carcass_readied_before_the_grid_still_registers() -> void:
	var carcass: Carcass = _make_carcass()
	var grid: SmellGrid = _make_grid()

	await wait_physics_frames(1)

	assert_almost_eq(grid.get_registered_smell_strength(carcass),
		carcass.profile.fresh_smell_strength, 0.01,
		"사체가 격자보다 먼저 준비돼도 냄새 원천으로 등록돼야 한다")


func test_removing_a_carcass_releases_its_smell_source() -> void:
	var grid: SmellGrid = _make_grid()
	var carcass: Carcass = _make_carcass()
	await wait_physics_frames(1)
	assert_eq(grid.get_registered_smell_source_count(), 1, "전제: 등록됨")

	carcass.free()

	assert_eq(grid.get_registered_smell_source_count(), 0, "사체가 사라지면 원천도 빠진다")


# --- 절단 소음 ---------------------------------------------------------------

func test_the_butcher_noise_profile_matches_the_canon() -> void:
	assert_eq(BUTCHER_NOISE.id, &"butcher")
	assert_almost_eq(BUTCHER_NOISE.radius, 240.0, 0.01, "절단 소음 240px (정본 §14.4)")
	assert_almost_eq(BUTCHER_NOISE.merge_window_seconds, 0.5, 0.01,
		"0.5초 안 반복은 병합 (정본 §14.4)")


func test_each_committed_stage_emits_one_cut_noise() -> void:
	var carcass: Carcass = _make_carcass()
	var player: Player = _make_butcher()
	var heard: Array = []
	_event_bus.noise_emitted.connect(func(position: Vector2, radius: float, _source: Node) -> void:
		if is_equal_approx(radius, BUTCHER_NOISE.radius):
			heard.append(position))

	assert_true(carcass.apply_stage(player), "구간 완료")

	assert_eq(heard.size(), 1, "구간 완료마다 절단 소음 1회")
	assert_eq(heard[0], carcass.global_position, "소음은 사체 위치에서 난다")


func test_a_failed_stage_makes_no_noise() -> void:
	# 산출이 안 들어가 실패한 구간은 아무 일도 없었던 것과 같아야 한다.
	var carcass: Carcass = _make_carcass()
	var player: Player = _make_butcher()
	var meat: ItemData = get_node("/root/GameData").get_item(&"raw_meat")
	var room: int = int((player.inventory.max_weight - player.inventory.total_weight()) / meat.weight)
	player.inventory.add_item(&"raw_meat", room)
	var heard: Array = []
	_event_bus.noise_emitted.connect(func(_position: Vector2, radius: float, _source: Node) -> void:
		if is_equal_approx(radius, BUTCHER_NOISE.radius):
			heard.append(radius))

	assert_false(carcass.apply_stage(player), "전제: 만석이라 구간 실패")

	assert_eq(heard.size(), 0, "실패한 구간은 소음도 내지 않는다")


## 정본 §14.4: "0.5초 안 반복은 병합". 두 명이 같은 사체를 동시에 해체해
## 구간이 겹쳐 끝나는 경우가 실제 대상이다.
func test_two_cuts_within_the_merge_window_are_merged() -> void:
	var carcass: Carcass = _make_carcass()
	var first: Player = _make_butcher()
	var second: Player = _make_butcher()
	var heard: Array = []
	_event_bus.noise_emitted.connect(func(_position: Vector2, radius: float, _source: Node) -> void:
		if is_equal_approx(radius, BUTCHER_NOISE.radius):
			heard.append(radius))

	assert_true(carcass.apply_stage(first))
	assert_true(carcass.apply_stage(second))

	assert_eq(heard.size(), 1, "병합 창 안의 두 절단은 한 번으로 합쳐진다")


func test_client_cannot_butcher_silently() -> void:
	# 정본 §14.4: "클라이언트가 조용한 완료를 주장할 수 없음".
	# 소음 권위는 해체 주체에 있다 — 권위 없는 주체의 발신은 나가지 않는다.
	var carcass: Carcass = _make_carcass()
	var player: Player = _make_butcher()
	player.set_multiplayer_authority(2)
	var heard: Array = []
	_event_bus.noise_emitted.connect(func(_position: Vector2, radius: float, _source: Node) -> void:
		if is_equal_approx(radius, BUTCHER_NOISE.radius):
			heard.append(radius))

	assert_true(carcass.apply_stage(player), "구간 자체는 로컬 경로로 확정된다")

	assert_eq(heard.size(), 0, "권위 없는 해체 주체는 소음을 발신하지 않는다")


## 대가가 위협으로 이어지는 고리: 절단 소음이 실제로 조사 목적지를 만든다.
func test_raptor_investigates_the_cut_noise() -> void:
	var carcass: Carcass = _make_carcass(Vector2(250.0, 250.0))
	var player: Player = _make_butcher(Vector2(250.0, 250.0))
	var data: CreatureData = CreatureDataScript.new()
	data.sight_radius = 50.0
	data.lose_sight_radius = 80.0
	data.smell_threshold = 8.0
	data.ai_tick_interval = 0.2
	data.occlusion_attenuation = 0.5
	var raptor: Raptor = RaptorScript.new()
	raptor.data = data
	# 절단 소음 반경(240px) 안, 시야(50px) 밖 — 소리로만 알아채는 상황을 만든다.
	raptor.position = Vector2(250.0 + BUTCHER_NOISE.radius - 40.0, 250.0)
	add_child_autofree(raptor)
	await wait_physics_frames(2)
	assert_eq(raptor.state, Raptor.State.WANDER, "전제: 배회 중")

	assert_true(carcass.apply_stage(player), "구간 완료 → 절단 소음 240px")
	await wait_physics_frames(2)
	raptor._ai_tick()

	assert_eq(raptor.state, Raptor.State.INVESTIGATE, "절단 소음을 들은 랩터가 조사에 들어간다")
	assert_eq(raptor.move_target, carcass.global_position, "조사 목표는 사체 위치다")


## 해체의 진짜 대가: 사체를 다 발라내 사체 냄새가 0 이 되어도, 그 고기를 들고 있는
## 해체자 본인이 냄새 원천이 된다. 정본 §14.4 "가방에 넣어도 냄새 삭제 안 함".
func test_the_butcher_carries_the_smell_away_with_the_meat() -> void:
	var grid: SmellGrid = _make_grid()
	var carcass: Carcass = _make_carcass(Vector2(150.0, 150.0))
	var player: Player = _make_butcher(Vector2(150.0, 150.0))
	for stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.apply_stage(player))
	assert_eq(grid.get_registered_smell_strength(carcass), 0.0, "전제: 사체는 골격이라 무취")

	player.global_position = Vector2(650.0, 650.0)
	grid._process(0.5)

	assert_gt(grid.get_smell_at(player.global_position), 0.0,
		"산출을 들고 이동하면 냄새가 따라온다 — 해체의 대가는 현장에서 끝나지 않는다")

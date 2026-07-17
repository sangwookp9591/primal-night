extends GutTest

## 사체 해체 홀드 골격 (W5-T1, 정본 §14.4).
##
## 계약: 홀드 1회 = 구간 1개(25%). 4구간이면 완전 해체다.
## 맨손 불가, 돌칼 8초/구간, 뼈 긁개 6초/구간(25% 감소) — 완전 해체 24~32초로
## 정본의 "한 사체 완전 해체 = 20~40초 노출"에 들어간다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CarcassScene: PackedScene = preload("res://scenes/props/carcass.tscn")

const STONE_KNIFE: StringName = &"stone_knife"
const BONE_SCRAPER: StringName = &"bone_scraper"

var _game_data: Node = null

func before_each() -> void:
	_game_data = get_node("/root/GameData")

func _make_player(at: Vector2 = Vector2.ZERO) -> Player:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	player.global_position = at
	return player

func _make_carcass(at: Vector2 = Vector2.ZERO) -> Carcass:
	var carcass: Carcass = add_child_autofree(CarcassScene.instantiate())
	carcass.global_position = at
	return carcass


func test_bare_hands_cannot_butcher() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()

	assert_false(carcass.can_interact(player), "맨손으로는 해체할 수 없다 (정본 §14.4)")


func test_stone_knife_enables_butchering_at_base_time() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)

	assert_true(carcass.can_interact(player), "돌칼을 들면 해체할 수 있다")
	assert_almost_eq(carcass.hold_seconds_for(player), carcass.profile.base_butcher_seconds, 0.01,
		"돌칼은 기준 시간 그대로다")


func test_bone_scraper_is_a_quarter_faster_than_stone_knife() -> void:
	var scraper_player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(scraper_player.inventory.add_item(BONE_SCRAPER, 1), 1)

	var scraper_seconds: float = carcass.hold_seconds_for(scraper_player)

	assert_almost_eq(scraper_seconds, carcass.profile.base_butcher_seconds * 0.75, 0.01,
		"뼈 긁개는 해체 시간 25% 감소 (정본 §14.2)")


func test_best_tool_wins_when_carrying_both() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	assert_eq(player.inventory.add_item(BONE_SCRAPER, 1), 1)

	assert_true(carcass.can_interact(player))
	assert_almost_eq(carcass.hold_seconds_for(player), carcass.profile.base_butcher_seconds * 0.75, 0.01,
		"둘 다 들면 더 빠른 도구를 쓴다")


## 정본 §14.4: "이동·피격·거리 72px 초과 시 중단, 진행은 사체에 저장"
func test_interrupted_hold_keeps_progress_on_the_carcass() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	var full: float = carcass.hold_seconds_for(player)

	carcass.on_hold_started(player)
	carcass._process(2.0)
	carcass.on_hold_ended(player)

	assert_almost_eq(carcass.hold_seconds_for(player), full - 2.0, 0.01,
		"중단해도 진행률이 사체에 남아 남은 시간만 다시 홀드한다")


func test_progress_resumes_across_two_separate_holds() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	var full: float = carcass.hold_seconds_for(player)

	carcass.on_hold_started(player)
	carcass._process(2.0)
	carcass.on_hold_ended(player)
	carcass.on_hold_started(player)
	carcass._process(3.0)
	carcass.on_hold_ended(player)

	assert_almost_eq(carcass.hold_seconds_for(player), full - 5.0, 0.01, "두 번에 나눠 해도 진행이 누적된다")


func test_committing_a_stage_resets_progress_for_the_next_stage() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	var full: float = carcass.hold_seconds_for(player)

	carcass.on_hold_started(player)
	carcass._process(full)
	carcass.interact(player)

	assert_eq(carcass.stages_done(), 1, "홀드 1회 = 구간 1개")
	assert_almost_eq(carcass.hold_seconds_for(player), full, 0.01, "다음 구간은 처음부터 다시 홀드한다")


func test_holder_leaving_the_butcher_radius_cancels_the_hold_but_keeps_progress() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)
	await wait_physics_frames(2)
	assert_eq(player.interactor.find_target(), carcass, "전제: 사체가 상호작용 대상")
	player.interactor.begin()
	assert_true(player.interactor._holding, "전제: 홀드 중")

	carcass._process(2.0)
	player.global_position = Vector2(Carcass.BUTCHER_MAX_DISTANCE_PX + 40.0, 0.0)
	carcass._process(0.1)

	assert_false(player.interactor._holding, "72px 밖으로 벗어나면 홀드가 끊긴다")
	assert_gt(carcass._stage_elapsed, 0.0, "끊겨도 진행은 사체에 남는다")


## 실기 경로 회귀: Interactor 는 `get_hold_seconds()` 를 인자 없이 부른다. 사체는
## can_interact(who) 직후라는 호출 순서에 기대어 도구를 안다. 그 결합이 깨지면
## 홀드 시간이 조용히 INF 가 되고 해체가 영원히 끝나지 않는다 — 단위 호출만 보는
## 테스트로는 안 잡힌다 (W5 의 cycle_target 교훈).
func test_interactor_picks_the_tool_time_through_the_argless_contract() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(BONE_SCRAPER, 1), 1)
	await wait_physics_frames(2)

	player.interactor.begin()

	assert_true(player.interactor._holding, "사체 홀드가 시작돼야 한다")
	assert_almost_eq(player.interactor._hold_required,
		carcass.profile.base_butcher_seconds * 0.75, 0.01,
		"Interactor 가 잡은 홀드 시간이 뼈 긁개 기준이어야 한다")


func test_full_butcher_takes_four_stages_and_then_offers_nothing() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)

	for stage: int in range(carcass.profile.stage_count):
		assert_true(carcass.can_interact(player), "구간 %d 전에는 해체할 수 있다" % stage)
		carcass.on_hold_started(player)
		carcass._process(carcass.hold_seconds_for(player))
		carcass.interact(player)

	assert_true(carcass.is_fully_butchered(), "%d구간이면 완전 해체다" % carcass.profile.stage_count)
	assert_false(carcass.can_interact(player), "골격만 남으면 더 해체할 수 없다")


func test_full_butcher_stays_within_the_canonical_exposure_window() -> void:
	# 정본 §14.4: "한 사체를 완전히 해체하면 20~40초를 노출"
	var carcass: Carcass = _make_carcass()
	var profile: CarcassProfile = carcass.profile

	var slowest: float = profile.base_butcher_seconds * float(profile.stage_count)
	var fastest: float = profile.base_butcher_seconds * 0.75 * float(profile.stage_count)

	assert_between(slowest, 20.0, 40.0, "돌칼 완전 해체가 20~40초 노출 안이어야 한다")
	assert_between(fastest, 20.0, 40.0, "뼈 긁개 완전 해체가 20~40초 노출 안이어야 한다")


func test_unknown_tool_cannot_butcher() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(&"stone", 1), 1)

	assert_false(carcass.can_interact(player), "해체 도구가 아닌 물건으로는 해체할 수 없다")


func test_prompt_comes_from_data_not_hardcoded_text() -> void:
	var player: Player = _make_player()
	var carcass: Carcass = _make_carcass()
	assert_eq(player.inventory.add_item(STONE_KNIFE, 1), 1)

	var prompt: String = carcass.get_prompt()

	assert_true(prompt.contains(carcass.profile.display_name),
		"표시 문구는 CarcassProfile 에서 온다 (설계서 5.6: UI 하드코딩 금지)")

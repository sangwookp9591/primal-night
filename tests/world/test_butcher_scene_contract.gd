extends GutTest

## main.tscn 배선 계약 (W5-T1~T3).
##
## 왜 필요한가: 유닛 테스트는 자기 하네스에 NetButcher 를 직접 세우고, 냄새 격자를
## 사체보다 먼저 만든다. 그래서 "실기 씬에 노드가 아예 없다" 와 "씬 노드 순서 탓에
## 등록이 실패한다" 를 **구조적으로** 잡을 수 없다. 실제로 두 건 다 이 방식으로
## 통과하는 척했고 계측으로만 드러났다 (W5 의 cycle_target 과 같은 부류).
##
## 씬을 실제로 인스턴스화해 확인한다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")


func test_main_scene_has_a_net_butcher_wired_like_the_other_authority_nodes() -> void:
	var main: Node = autofree(MainScene.instantiate())

	var butcher: NetButcher = main.get_node_or_null("NetButcher") as NetButcher
	assert_not_null(butcher, "main.tscn 에 NetButcher 가 없으면 해체가 로컬 경로로 떨어져 "
		+ "클라이언트가 즉시 완료를 주장할 수 있다")
	if butcher == null:
		return

	# 경로 규약은 NetPickup 과 같아야 한다 — 같은 월드 루트/세션/아바타를 봐야
	# 호스트 판정이 같은 사실 위에서 이뤄진다.
	var pickup: NetPickup = main.get_node_or_null("NetPickup") as NetPickup
	assert_not_null(pickup, "전제: NetPickup 이 기준 규약이다")
	if pickup == null:
		return
	assert_eq(butcher.session_path, pickup.session_path, "세션 경로 규약이 같아야 한다")
	assert_eq(butcher.host_player_path, pickup.host_player_path, "호스트 아바타 경로 규약이 같아야 한다")
	assert_eq(butcher.players_container_path, pickup.players_container_path,
		"아바타 컨테이너 경로 규약이 같아야 한다")
	assert_eq(butcher.world_root_path, pickup.world_root_path, "월드 루트 경로 규약이 같아야 한다")


func test_main_scene_seeds_a_reachable_carcass() -> void:
	var main: Node = autofree(MainScene.instantiate())

	var carcass: Carcass = main.get_node_or_null("SurvivalDemo/RaptorCarcass") as Carcass
	assert_not_null(carcass, "해체할 사체가 월드에 없으면 W5~6 루프가 플레이 불가다")
	if carcass == null:
		return
	assert_not_null(carcass.profile, "사체에 프로필이 붙어 있어야 한다")
	assert_true(carcass.profile.is_valid(), "사체 프로필이 유효해야 한다")


## 계측으로 발견한 실기 버그의 회귀: main.tscn 은 SurvivalDemo 를 SmellGrid **앞**에
## 둔다. 사체가 _ready 에서 곧장 격자를 찾으면 그룹이 아직 비어 있어 신선한 사체가
## 무취가 된다 — 이 마일스톤의 위험 절반이 조용히 죽는다.
func test_seeded_carcass_registers_its_smell_in_the_real_scene_order() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)

	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var grid: SmellGrid = main.get_node("SmellGrid")

	assert_almost_eq(grid.get_registered_smell_strength(carcass),
		carcass.profile.fresh_smell_strength, 0.01,
		"실기 씬 순서에서도 신선한 사체가 피 냄새 80 을 등록해야 한다")


## 사체가 모닥불 회피 반경 안에 있으면 해체의 대가가 사라진다 (랩터가 접근 못 함).
func test_seeded_carcass_is_not_sheltered_by_the_campfire_site() -> void:
	var main: Node = autofree(MainScene.instantiate())
	var carcass: Carcass = main.get_node("SurvivalDemo/RaptorCarcass")
	var site: Node2D = main.get_node("SurvivalDemo/CampfireSite")

	assert_gt(carcass.position.distance_to(site.position), 100.0,
		"사체가 모닥불 자리에 붙어 있으면 위험·보상 루프가 성립하지 않는다")

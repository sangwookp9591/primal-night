extends GutTest

## 냄새 원천 등록의 실기 씬 계약.
##
## 왜 별도 파일인가: tests/senses/test_smell_source.gd 는 격자를 먼저 만들고 원천을
## 나중에 붙인다. 그 순서에서는 등록이 항상 성공하므로 **실기 순서 버그를 원리적으로
## 잡을 수 없다**. main.tscn 은 반대로 SurvivalDemo(바닥 아이템)를 SmellGrid **앞**에
## 두기 때문에, SmellSource 가 _ready 에서 곧장 격자를 찾으면 smell_grid 그룹이 아직
## 비어 있어 조용히 등록에 실패한다.
##
## 실제로 그랬다: W3-T4 이후 바닥 raw_meat 은 실기에서 한 번도 냄새를 낸 적이 없고
## (등록 강도 0.0), GUT 는 전부 초록이었다. 그래서 씬을 진짜로 로드해 확인한다.
## (같은 부류: tests/world/test_butcher_scene_contract.gd)

const MainScene: PackedScene = preload("res://scenes/main.tscn")


func _smell_source_under(node: Node) -> SmellSource:
	for child: Node in node.get_children():
		if child is SmellSource:
			return child as SmellSource
	return null


func test_scene_orders_survival_demo_before_the_smell_grid() -> void:
	# 이 테스트가 지키는 것은 "순서를 고치라"가 아니라 "아래 테스트들이 여전히 의미
	# 있는 순서를 시험하고 있다"는 전제다. 순서가 뒤집히면 회귀 테스트가 무력해진다.
	var main: Node = autofree(MainScene.instantiate())
	var names: Array[String] = []
	for child: Node in main.get_children():
		names.append(child.name)

	assert_lt(names.find("SurvivalDemo"), names.find("SmellGrid"),
		"main.tscn 은 SurvivalDemo 를 SmellGrid 앞에 둔다 — 등록 순서 버그가 재현되는 배치다")


func test_floor_raw_meat_registers_its_smell_in_the_real_scene() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)
	var meat: Node2D = main.get_node("SurvivalDemo/RawMeat")
	var grid: SmellGrid = main.get_node("SmellGrid")

	var source: SmellSource = _smell_source_under(meat)

	assert_not_null(source, "바닥 raw_meat 에 냄새 원천 노드가 붙어 있어야 한다")
	if source == null:
		return
	assert_gt(grid.get_registered_smell_strength(source), 0.0,
		"실기 씬 순서에서도 바닥 raw_meat 이 냄새 원천으로 등록돼야 한다")


func test_floor_raw_meat_actually_emits_smell_in_the_real_scene() -> void:
	# 등록만으로는 부족하다 — 실제로 격자에 냄새가 쌓이는지까지 본다.
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)
	var meat: Node2D = main.get_node("SurvivalDemo/RawMeat")
	var grid: SmellGrid = main.get_node("SmellGrid")

	grid._process(1.0)

	assert_gt(grid.get_smell_at(meat.global_position), 0.0,
		"바닥 raw_meat 위치에서 실제로 냄새가 나야 한다 (W3-T4 의 판매 포인트다)")


func test_every_seeded_smell_source_in_the_scene_is_registered() -> void:
	# 사체든 바닥 아이템이든, 씬에 시드 배치된 냄새 원천은 예외 없이 등록돼야 한다.
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)
	var grid: SmellGrid = main.get_node("SmellGrid")

	var checked: int = 0
	for node: Node in main.find_children("*", "", true, false):
		if not (node is SmellSource):
			continue
		checked += 1
		assert_gt(grid.get_registered_smell_strength(node), 0.0,
			"%s 가 등록되지 않았다" % main.get_path_to(node))
	assert_gt(checked, 0, "전제: 씬에 시드 배치된 SmellSource 가 있다")

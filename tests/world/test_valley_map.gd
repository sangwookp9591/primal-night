extends GutTest

## 40청크 계곡 맵 계약 (레인 M, MAP_DESIGN_DRAFT §2/§3/§9).
##
## 지키는 것: 배치도(문서 §2)와 코드 배치가 일치하는가, 랜드마크가 문서 청크 좌표에
## 있는가, 그리고 ★가장 중요한★ 기존 게임플레이 좌표가 여전히 플레이 가능한 Zone 위에
## 있는가(하네스 좌표 의존이 깨지지 않았는가).

const ValleyScene: PackedScene = preload("res://scenes/world/valley.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const ValleyMapScript = preload("res://scripts/world/valley_map.gd")

## main.tscn 의 불변 게임플레이 좌표 (이 값이 바뀌면 하네스가 깨진다).
const GAMEPLAY_COORDS: Dictionary = {
	"Player": Vector2(-384, 200),
	"Carcass": Vector2(-300, 300),
	"Campfire": Vector2(-190, 330),
	"LoopObjective": Vector2(640, 700),
	"Raptor": Vector2(-800, 800),
	"Raptor2": Vector2(-1040, 760),
}


func _make_valley() -> ValleyMap:
	var valley: ValleyMap = ValleyScene.instantiate()
	add_child_autofree(valley)
	return valley


# --- 배치도 계약 (문서 §2/§9) ------------------------------------------------

func test_scene_has_isometric_layers_and_navigation() -> void:
	# 기존 test_world_contract 와 같은 계약을 valley 도 만족해야 교체가 안전하다.
	var valley: ValleyMap = _make_valley()
	var ground: TileMapLayer = valley.get_node("Ground")
	var collision: TileMapLayer = valley.get_node("Collision")
	var occlusion: TileMapLayer = valley.get_node("Occlusion")
	var navigation: NavigationRegion2D = valley.get_node("NavigationRegion2D")

	assert_not_null(ground)
	assert_not_null(collision)
	assert_not_null(occlusion)
	assert_not_null(navigation)
	assert_eq(ground.tile_set.tile_shape, TileSet.TILE_SHAPE_ISOMETRIC)
	assert_eq(ground.tile_set.tile_size, Vector2i(64, 32))
	assert_true(ground.y_sort_enabled)
	assert_true(collision.y_sort_enabled)
	assert_true(occlusion.y_sort_enabled)


func test_exactly_forty_playable_chunks() -> void:
	# 문서 §9 자체 점검: 6+8+10+8+8 = 40.
	var valley: ValleyMap = _make_valley()
	assert_eq(valley.playable_chunk_count(), 40, "플레이 가능 청크는 40개다 (정본 §10 MVP)")


func test_zone_chunk_counts_match_the_document() -> void:
	# 배치도 라벨을 세어 Zone별 수량이 문서 표와 일치하는지 검산한다.
	var counts: Dictionary = {}
	for row: Array in ValleyMapScript.DOC_GRID:
		for label: String in row:
			if label == "··":
				continue
			var zone: String = label.substr(0, 1)
			counts[zone] = int(counts.get(zone, 0)) + 1

	assert_eq(counts.get("1", 0), 6, "Z01 = 6청크")
	assert_eq(counts.get("2", 0), 8, "Z02 = 8청크")
	assert_eq(counts.get("3", 0), 10, "Z03 = 10청크")
	assert_eq(counts.get("4", 0), 8, "Z04 = 8청크")
	assert_eq(counts.get("5", 0), 8, "Z05 = 8청크")


func test_doc_grid_is_eight_by_eight() -> void:
	assert_eq(ValleyMapScript.DOC_GRID.size(), 8, "8행")
	for row: Array in ValleyMapScript.DOC_GRID:
		assert_eq(row.size(), 8, "각 행 8열 (8×8 경계)")


func test_chunk_labels_are_unique() -> void:
	# 같은 라벨이 두 청크에 나오면 배치도 오타다.
	var seen: Dictionary = {}
	for row: Array in ValleyMapScript.DOC_GRID:
		for label: String in row:
			if label == "··":
				continue
			assert_false(seen.has(label), "청크 라벨 %s 가 중복됐다" % label)
			seen[label] = true
	assert_eq(seen.size(), 40, "고유 플레이 청크 40개")


func test_ground_paints_exactly_forty_chunks_worth_of_tiles() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)
	var ground: TileMapLayer = valley.get_node("Ground")

	# 40청크 × 32×32 = 40960 타일.
	assert_eq(ground.get_used_cells().size(), 40 * 32 * 32,
		"플레이 청크 40개가 각각 1024 타일로 칠해져야 한다")


func test_nonplay_chunks_are_collision() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)
	var collision: TileMapLayer = valley.get_node("Collision")

	# 24 비플레이 청크 × 1024 = 24576 충돌 타일.
	assert_eq(collision.get_used_cells().size(), 24 * 32 * 32,
		"비플레이 청크는 충돌 타일로 칠해져야 한다 (이동 불가)")
	# 충돌 타일은 물리 폴리곤을 가진다 (아틀라스 5번).
	var sample: Vector2i = collision.get_used_cells()[0]
	assert_eq(collision.get_cell_atlas_coords(sample), Vector2i(ValleyMapScript.TILE_NONPLAY, 0),
		"비플레이 타일은 절벽/물 아틀라스여야 한다")


# --- 랜드마크 계약 (문서 §3) -------------------------------------------------

func test_all_sixteen_landmarks_are_placed() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)
	var container: Node2D = valley.get_node("Landmarks")

	for landmark_id: String in ValleyMapScript.LANDMARKS:
		assert_not_null(container.get_node_or_null(landmark_id),
			"랜드마크 %s 마커가 배치돼야 한다" % landmark_id)


func test_landmark_count_matches_the_document() -> void:
	# S01~S10(10) + F1~F3(3) + R1~R2(2) + H1(1) = 16.
	assert_eq(ValleyMapScript.LANDMARKS.size(), 16, "랜드마크 16개 (S10 + F3 + R2 + H1)")
	var campfire_anchors: int = 0
	for landmark_id: String in ValleyMapScript.LANDMARKS:
		if landmark_id.begins_with("F"):
			campfire_anchors += 1
	# 모닥불 지정 자리는 S02 + F1/F2/F3 = 4개 (문서 §3). F 표식은 그중 3개.
	assert_eq(campfire_anchors, 3, "F 표식 모닥불 자리는 3개 (S02 포함 총 4개)")


func test_landmark_sits_on_its_documented_chunk() -> void:
	# S01 은 1E=(1,1), S10 은 5B=(3,7). 마커가 그 청크 안에 있어야 한다.
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)

	for check: Array in [["S01", Vector2i(1, 1)], ["S10", Vector2i(3, 7)], ["H1", Vector2i(5, 5)]]:
		var landmark_id: String = check[0]
		var doc_coord: Vector2i = check[1]
		var world: Vector2 = valley.landmark_world_position(landmark_id)
		# 랜드마크 월드 좌표를 다시 Zone 으로 되짚으면 그 청크의 Zone 과 맞아야 한다.
		var expected_zone: String = "Z0%s" % ValleyMapScript.DOC_GRID[(8 - 1) - doc_coord.y][doc_coord.x].substr(0, 1)
		assert_eq(valley.zone_at_world(world), expected_zone,
			"%s 마커가 문서 청크(%s)의 Zone 위에 있어야 한다" % [landmark_id, doc_coord])


# --- ★ 게임플레이 좌표 불변 계약 --------------------------------------------

func test_gameplay_coordinates_stay_on_playable_zone01() -> void:
	# 하네스·게임플레이는 이 좌표에 의존한다. 맵 오프셋이 어긋나 이 좌표가 비플레이
	# 위로 가면 플레이어가 벽에 스폰되거나 랩터가 못 움직인다.
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)

	for name: String in GAMEPLAY_COORDS:
		var zone: String = valley.zone_at_world(GAMEPLAY_COORDS[name])
		assert_eq(zone, "Z01",
			"%s 좌표 %s 는 시작 지역 Z01(플레이 가능) 위에 있어야 한다 (관측 '%s')" % [
				name, GAMEPLAY_COORDS[name], zone])


func test_gameplay_coordinates_are_not_on_collision_tiles() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)
	var collision: TileMapLayer = valley.get_node("Collision")

	for name: String in GAMEPLAY_COORDS:
		var local: Vector2 = GAMEPLAY_COORDS[name] - ValleyMapScript.MAP_PIXEL_OFFSET
		var cell: Vector2i = collision.local_to_map(local)
		assert_eq(collision.get_cell_source_id(cell), -1,
			"%s 좌표에 충돌 타일이 있으면 안 된다 (플레이어가 벽에 낀다)" % name)


# --- main.tscn 실씬 통합 계약 ------------------------------------------------

func test_main_scene_uses_the_valley_world_with_intact_gameplay_coords() -> void:
	var main: Node = add_child_autofree(MainScene.instantiate())
	await wait_physics_frames(2)

	var world: Node = main.get_node("World")
	assert_true(world is ValleyMap, "main.tscn 의 World 는 valley 여야 한다")

	# 게임플레이 노드 좌표가 문서 교체로 바뀌지 않았는지 실제 씬에서 확인한다.
	assert_eq((main.get_node("Player") as Node2D).position, Vector2(-384, 200), "Player 좌표 불변")
	assert_eq((main.get_node("Raptor") as Node2D).position, Vector2(-800, 800), "Raptor 좌표 불변")
	assert_eq((main.get_node("Raptor2") as Node2D).position, Vector2(-1040, 760), "Raptor2 좌표 불변")
	assert_eq((main.get_node("LoopObjective") as Node2D).position, Vector2(640, 700), "LoopObjective 좌표 불변")

	# 그 좌표들이 valley 의 플레이 가능 Zone 위에 있는지도 실씬에서 확인한다.
	var valley: ValleyMap = world as ValleyMap
	assert_eq(valley.zone_at_world((main.get_node("Player") as Node2D).position), "Z01",
		"실씬에서도 플레이어 스폰이 Z01 위여야 한다")

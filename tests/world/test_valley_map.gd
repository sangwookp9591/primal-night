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


func _world_for_ground_cell(valley: ValleyMap, cell: Vector2i) -> Vector2:
	var ground: TileMapLayer = valley.get_node("Ground")
	return ValleyMapScript.MAP_PIXEL_OFFSET + ground.map_to_local(cell)


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
	# 평면 타일 레이어는 y-sort 금지 — 쿼드런트(청크) 단위 정렬로 대형 스프라이트가
	# 직선으로 잘리는 아티팩트의 원인. 전역 정렬은 World 루트 y-sort가 담당한다.
	assert_false(ground.y_sort_enabled)
	assert_false(collision.y_sort_enabled)
	assert_false(occlusion.y_sort_enabled)
	assert_true(valley.y_sort_enabled,
		"World 루트가 y-sort 체인을 제공해야 크리처·식생 가림 순서가 성립한다")


func test_open_slice_has_dense_collision_free_y_sorted_vegetation() -> void:
	var valley: ValleyMap = _make_valley()
	var vegetation := valley.get_node_or_null("Vegetation") as Node2D
	assert_not_null(vegetation)
	assert_true(vegetation.y_sort_enabled)
	assert_gt(vegetation.get_child_count(), 350,
		"Z01~Z03에는 화면 격자를 끊을 만큼 결정적 식생 소품이 있어야 한다")
	assert_lt(vegetation.get_child_count(), 650,
		"장식 밀도는 렌더·노드 예산 안에 머물러야 한다")
	var tall_tree_count := 0
	for node: Node in vegetation.get_children():
		assert_true(node is Sprite2D)
		assert_false(node is CollisionObject2D)
		var region := (node as Sprite2D).region_rect
		if region.position.y == 0.0:
			tall_tree_count += 1
	assert_gt(tall_tree_count, 20, "캐릭터보다 큰 나무가 여러 구역에 충분히 배치되어야 한다")


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
	# 모든 비플레이 타일은 절벽 또는 깊은 물 아틀라스여야 한다 (정식 지형 시트).
	var nonplay_atlases: Array = [ValleyMapScript.TILE_CLIFF, ValleyMapScript.TILE_WATER]
	for sample: Vector2i in collision.get_used_cells():
		assert_true(collision.get_cell_atlas_coords(sample) in nonplay_atlases,
			"비플레이 타일 %s 는 절벽/물 아틀라스여야 한다" % sample)


func test_nonplay_tiles_carry_collision_polygons() -> void:
	# 절벽·물 타일이 실제로 물리 폴리곤을 가져야 이동이 막힌다.
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)
	var tile_set: TileSet = (valley.get_node("Collision") as TileMapLayer).tile_set
	var source: TileSetAtlasSource = tile_set.get_source(ValleyMapScript.SOURCE_ID) as TileSetAtlasSource

	for atlas: Vector2i in [ValleyMapScript.TILE_CLIFF, ValleyMapScript.TILE_WATER]:
		var data: TileData = source.get_tile_data(atlas, 0)
		assert_gt(data.get_collision_polygons_count(0), 0,
			"비플레이 타일 %s 는 충돌 폴리곤을 가져야 한다" % atlas)


func test_playable_zone_tiles_come_from_the_zone_variant_set() -> void:
	# 각 Zone 청크의 타일이 그 Zone 의 변형 집합에서만 나오는지 검산한다.
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)
	var ground: TileMapLayer = valley.get_node("Ground")

	# S01(Z01, 1E) 청크의 셀들이 Z01 변형만 쓰는지 표본 확인.
	var origin: Vector2i = ValleyMapScript.chunk_cell_origin(Vector2i(1, 1))
	var z01_variants: Array = ValleyMapScript.ZONE_VARIANTS["1"]
	var seen_variety: Dictionary = {}
	for dy: int in range(0, ValleyMapScript.TILES_PER_CHUNK, 4):
		for dx: int in range(0, ValleyMapScript.TILES_PER_CHUNK, 4):
			var atlas: Vector2i = ground.get_cell_atlas_coords(origin + Vector2i(dx, dy))
			assert_true(atlas in z01_variants, "Z01 청크 타일 %s 는 Z01 변형이어야 한다" % atlas)
			seen_variety[atlas] = true
	# 변형이 실제로 분산됐는지 — 한 종류만 나오면 시드 분산이 죽은 것이다.
	assert_gt(seen_variety.size(), 1, "Zone 변형이 청크 안에서 분산돼야 한다 (반복감 감소)")


func test_variant_selection_is_deterministic() -> void:
	# 같은 셀은 항상 같은 변형 — 실행마다 달라지면 하네스 결정성이 깨진다.
	for cell: Vector2i in [Vector2i(5, 7), Vector2i(40, 190), Vector2i(200, 12)]:
		var first: int = ValleyMapScript.variant_index(cell, 3)
		var second: int = ValleyMapScript.variant_index(cell, 3)
		assert_eq(first, second, "셀 %s 변형 선택은 결정적이어야 한다" % cell)
		assert_between(first, 0, 2, "변형 인덱스는 범위 안이어야 한다")


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


func test_zone_lookup_rejects_negative_boundary_cells_instead_of_truncating_to_z03() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)

	var west_of_z03_row := Vector2i(-1, 4 * ValleyMapScript.TILES_PER_CHUNK + 16)
	var north_of_map := Vector2i(2 * ValleyMapScript.TILES_PER_CHUNK + 16, -1)

	assert_eq(valley.zone_at_world(_world_for_ground_cell(valley, west_of_z03_row)), "",
		"서쪽 경계 밖 음수 셀은 col 0의 Z03 청크로 잘리면 안 된다")
	assert_eq(valley.zone_at_world(_world_for_ground_cell(valley, north_of_map)), "",
		"북쪽 경계 밖 음수 셀은 row 0 청크로 잘리면 안 된다")


func test_zone_lookup_rejects_exactly_outside_chunk_edges() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)

	var east_edge := Vector2i(ValleyMapScript.GRID * ValleyMapScript.TILES_PER_CHUNK, 64)
	var south_edge := Vector2i(64, ValleyMapScript.GRID * ValleyMapScript.TILES_PER_CHUNK)

	assert_eq(valley.zone_at_world(_world_for_ground_cell(valley, east_edge)), "")
	assert_eq(valley.zone_at_world(_world_for_ground_cell(valley, south_edge)), "")


func test_long_distance_chronicle_samples_do_not_record_unvisited_z03_from_west_boundary() -> void:
	var valley: ValleyMap = _make_valley()
	await wait_physics_frames(1)
	var chronicle := add_child_autofree(CharacterChronicle.new()) as CharacterChronicle
	var z01_sample := _world_for_ground_cell(
		valley, ValleyMapScript.chunk_cell_origin(Vector2i(1, 1)) + Vector2i(16, 16))
	var z02_sample := _world_for_ground_cell(
		valley, ValleyMapScript.chunk_cell_origin(Vector2i(4, 2)) + Vector2i(16, 16))
	var off_map_west_sample := _world_for_ground_cell(
		valley, Vector2i(-1, 4 * ValleyMapScript.TILES_PER_CHUNK + 16))

	chronicle.track_position_sample(z01_sample, valley.zone_at_world(z01_sample))
	chronicle.track_position_sample(z02_sample, valley.zone_at_world(z02_sample))
	chronicle.track_position_sample(off_map_west_sample, valley.zone_at_world(off_map_west_sample))

	assert_eq(Array(chronicle.visited_zones), ["Z01", "Z02"])


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

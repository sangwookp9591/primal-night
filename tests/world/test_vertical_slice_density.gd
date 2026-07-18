extends GutTest

const ValleyMapScript = preload("res://scripts/world/valley_map.gd")
const ValleyScene: PackedScene = preload("res://scenes/world/valley.tscn")


func test_vertical_slice_is_connected_z01_z02_z03_without_expanding_world() -> void:
	assert_eq(Array(ValleyMapScript.SLICE_ZONES), ["Z01", "Z02", "Z03"])
	assert_eq(Array(ValleyMapScript.LOCKED_ZONES), ["Z04", "Z05"])
	var playable := 0
	for row: Array in ValleyMapScript.DOC_GRID:
		for label: String in row:
			playable += int(label != "··")
	assert_eq(playable, 40, "수직 절편은 40청크 지형을 재생성하거나 확장하지 않는다")


func test_locked_exits_use_natural_obstacle_tiles() -> void:
	assert_eq(ValleyMapScript.SLICE_BOUNDARIES.size(), 3)
	for boundary: Dictionary in ValleyMapScript.SLICE_BOUNDARIES:
		assert_true(boundary.from in ValleyMapScript.SLICE_ZONES)
		assert_true(boundary.to in ValleyMapScript.LOCKED_ZONES)
		assert_true(boundary.terrain in ["절벽", "급류", "가시덤불"])
		assert_true(boundary.tile in [
			ValleyMapScript.TILE_CLIFF, ValleyMapScript.TILE_WATER, Vector2i(5, 2)])


func test_locked_exits_are_physically_painted_but_the_far_world_remains_visible() -> void:
	var valley: ValleyMap = ValleyScene.instantiate()
	add_child_autofree(valley)
	await wait_physics_frames(1)
	var boundary: TileMapLayer = valley.get_node("SliceBoundary")
	assert_gt(boundary.get_used_cells().size(), 0, "절편 밖 seam은 충돌 자연 타일로 막힌다")
	assert_lt(boundary.get_used_cells().size(), 16 * 32 * 32,
		"Z04/Z05 전체를 벽으로 칠하지 않아 이어지는 세계가 보인다")
	for cell: Vector2i in boundary.get_used_cells():
		assert_true(boundary.get_cell_atlas_coords(cell) in [
			ValleyMapScript.TILE_CLIFF, ValleyMapScript.TILE_WATER, Vector2i(5, 2)])


func test_every_slice_zone_meets_interaction_density_floor() -> void:
	var minimums: Dictionary = ValleyMapScript.DENSITY_RULES.minimum_interactions_per_zone
	for zone: String in ValleyMapScript.SLICE_ZONES:
		var count := 0
		for encounter: Dictionary in ValleyMapScript.SLICE_ENCOUNTERS:
			count += int(encounter.zone == zone)
		assert_gte(count, int(minimums[zone]), "%s 상호작용 밀도" % zone)
	assert_eq(ValleyMapScript.DENSITY_RULES.travel_seconds_min, 30)
	assert_eq(ValleyMapScript.DENSITY_RULES.travel_seconds_max, 60)


func test_start_radius_bands_escalate_density_and_cover_fire_and_bandage() -> void:
	var bands: Array = ValleyMapScript.DENSITY_RULES.start_radius_bands
	assert_eq(bands.size(), 3)
	assert_eq([bands[0].radius_px, bands[1].radius_px, bands[2].radius_px], [180, 360, 720])
	assert_eq([bands[0].minimum, bands[1].minimum, bands[2].minimum], [3, 6, 9])
	var early_refs: Array[String] = []
	for encounter: Dictionary in ValleyMapScript.SLICE_ENCOUNTERS:
		if encounter.zone == "Z01" and float(encounter.minute) <= 3.0:
			early_refs.append(encounter.ref)
	assert_true("bandage" in early_refs, "시작 반경에 즉시 치료 수단이 있다")
	assert_true("fiber" in early_refs, "붕대 대체 재료인 섬유가 있다")
	assert_true("wood" in early_refs, "추위 뒤 불의 마른 나무가 있다")
	assert_true("campfire_shelter" in early_refs, "재료 뒤 모닥불 바람막이가 있다")


func test_first_ten_minutes_teach_trace_before_safe_distance_raptor() -> void:
	var trace_minute := INF
	var danger_minute := INF
	for encounter: Dictionary in ValleyMapScript.SLICE_ENCOUNTERS:
		if encounter.kind == "trace":
			trace_minute = minf(trace_minute, float(encounter.minute))
		if encounter.kind == "danger":
			danger_minute = minf(danger_minute, float(encounter.minute))
	assert_lt(trace_minute, danger_minute, "흔적을 읽은 뒤 공룡 위험을 만난다")
	assert_eq(ValleyMapScript.RAPTOR_DAY_ONE_PATROL.zone, "Z01")
	assert_gte(ValleyMapScript.RAPTOR_DAY_ONE_PATROL.minimum_safe_distance_from_spawn_px, 360.0)
	assert_lte(danger_minute, 10.0)


func test_encounters_only_reuse_existing_items_and_landmarks() -> void:
	var allowed_resources := ["bandage", "fiber", "wood", "stone"]
	for encounter: Dictionary in ValleyMapScript.SLICE_ENCOUNTERS:
		assert_true(encounter.zone in ValleyMapScript.SLICE_ZONES)
		assert_between(float(encounter.minute), 0.0, 10.0)
		if encounter.kind == "resource":
			assert_true(encounter.ref in allowed_resources, "새 아이템을 추가하지 않는다")

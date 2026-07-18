class_name ValleyMap
extends Node2D

## 40청크 계곡 회색 상자 (MAP_DESIGN_DRAFT §2/§3, 정본 §7~§10).
##
## 8×8 청크(각 32×32 아이소메트릭 64×32px 타일). 40개는 플레이 가능(Zone별 색),
## 나머지는 비플레이(절벽/물, 충돌). 청크·충돌·내비게이션을 _ready 에서
## 프로그램으로 칠하고, 랜드마크 시각 배치는 landmarks.tscn 이 단독 소유한다.
##
## 좌표 계약(★ 하네스·게임플레이 좌표 불변): main.tscn 의 Player(-384,200)·사체·
## 캠프파이어·LoopObjective(640,700)·랩터 좌표는 바뀌지 않는다. 대신 이 맵을
## MAP_PIXEL_OFFSET 만큼 밀어 Z01(시작 지역)이 그 좌표들을 덮게 한다.
## tests/world/test_valley_map.gd 가 이 불변식을 지킨다.

const TILES_PER_CHUNK: int = 32
const GRID: int = 8

const SOURCE_ID: int = 0

## 정식 지형 시트(valley_terrain_tiles_sheet, 6열×3행) 아틀라스 좌표.
## Zone 별 2~3 변형을 셀 시드로 분산 배치해 반복감을 줄인다.
const ZONE_VARIANTS: Dictionary = {
	"1": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],  # Z01 회갈 암반·다진 흙·추락 잔해
	"2": [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)],  # Z02 습지·얕은 물가·성긴 갈대
	"3": [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # Z03 짙은 식생·낙엽·거목 뿌리
	"4": [Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)],  # Z04 마른 풀·짓밟힌 흙·관목
	"5": [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)],  # Z05 현무암·화산암·화산재
}

## 비플레이(충돌) 지형 — 절벽/깊은 물.
const TILE_CLIFF: Vector2i = Vector2i(3, 2)
const TILE_WATER: Vector2i = Vector2i(4, 2)

## 지형 변형 분산용 고정 밸리 시드. 실행마다 같은 배치라 하네스 결정성이 유지된다.
const VALLEY_SEED: int = 0x5A11E9

## 배치도 §2. 행은 위(y7)→아래(y0). "··" 는 비플레이.
const DOC_GRID: Array = [
	["··", "··", "5A", "5B", "5C", "5D", "··", "··"],  # y7
	["··", "5E", "5F", "5G", "5H", "4A", "4B", "··"],  # y6
	["··", "3A", "3B", "4C", "4D", "4E", "4F", "··"],  # y5
	["3C", "3D", "3E", "3F", "4G", "4H", "··", "··"],  # y4
	["3G", "3H", "3I", "3J", "2A", "2B", "··", "··"],  # y3
	["1A", "1B", "1C", "2C", "2D", "2E", "··", "··"],  # y2
	["1D", "1E", "1F", "2F", "2G", "2H", "··", "··"],  # y1
	["··", "··", "··", "··", "··", "··", "··", "··"],  # y0
]

## 랜드마크 ID → 배치도 청크 좌표 (dcx, dcy) (§3). 기능은 범위 밖 — 위치·이름만.
const LANDMARKS: Dictionary = {
	"S01": Vector2i(1, 1), "S02": Vector2i(2, 2), "S03": Vector2i(4, 2),
	"S04": Vector2i(5, 1), "S05": Vector2i(2, 5), "S06": Vector2i(3, 3),
	"S07": Vector2i(1, 4), "S08": Vector2i(4, 5), "S09": Vector2i(4, 4),
	"S10": Vector2i(3, 7), "F1": Vector2i(3, 2), "F2": Vector2i(3, 4),
	"F3": Vector2i(3, 5), "R1": Vector2i(5, 3), "R2": Vector2i(1, 5),
	"H1": Vector2i(5, 5),
}

const LANDMARK_LABELS: Dictionary = {
	"S01": "S01 균열 추락흔", "S02": "S02 현무암 바람막이", "S03": "S03 붉은 갈대 웅덩이",
	"S04": "S04 침수 관측소", "S05": "S05 울음 골", "S06": "S06 메아리 동굴",
	"S07": "S07 갈고리턱 둥지", "S08": "S08 방패뿔 산란환", "S09": "S09 무리 횡단 수로",
	"S10": "S10 검은 능선 신호대", "F1": "F1 모닥불 자리", "F2": "F2 마른 굴",
	"F3": "F3 서쪽 바람막이", "R1": "R1 낮은 여울", "R2": "R2 덩굴 절벽", "H1": "H1 해체 고보상",
}

## ★ Z01(시작 지역)이 현재 플레이 영역(원점 부근)을 덮도록 맵을 민다.
## 값 근거: Z01 셀 중심(약 cell 48,191)의 아이소메트릭 투영을 플레이 중심(약 -200,500)에
## 맞춘 뒤 tests/world/test_valley_map.gd 가 실제 게임플레이 좌표를 검산해 확정한 값이다.
const MAP_PIXEL_OFFSET: Vector2 = Vector2(-3272.0, -2572.0)

## Phase 7 수직 절편. 40청크 원본은 보존하되 이 세 구역만 현재 플레이 동선으로 연다.
## Z01(안전/불) → Z02(물/회복) → Z03(재료/은신)는 정본 §10의 양방향 연결 삼각형이다.
const SLICE_ZONES: PackedStringArray = ["Z01", "Z02", "Z03"]
const LOCKED_ZONES: PackedStringArray = ["Z04", "Z05"]

## 열린 세계의 가장자리처럼 보이는 자연 경계. 다음 Phase가 해제할 때 타일맵을
## 재생성하지 않고 이 경계 데이터만 제거할 수 있다.
const SLICE_BOUNDARIES: Array[Dictionary] = [
	{"from": "Z02", "to": "Z04", "terrain": "급류", "tile": TILE_WATER},
	{"from": "Z03", "to": "Z04", "terrain": "가시덤불", "tile": Vector2i(5, 2)},
	{"from": "Z03", "to": "Z05", "terrain": "절벽", "tile": TILE_CLIFF},
]

## 보행 30~60초마다 하나의 판단을 주는 고정 앵커. 기존 아이템/랜드마크/랩터만
## 재배치 대상으로 참조하며 새 아이템·레시피를 만들지 않는다.
const DENSITY_RULES: Dictionary = {
	"travel_seconds_min": 30,
	"travel_seconds_max": 60,
	"minimum_interactions_per_zone": {"Z01": 6, "Z02": 6, "Z03": 6},
	"start_radius_bands": [
		{"radius_px": 180, "minimum": 3, "purpose": "부상 안정화와 첫 채집"},
		{"radius_px": 360, "minimum": 6, "purpose": "불 재료와 바람막이"},
		{"radius_px": 720, "minimum": 9, "purpose": "흔적 뒤 첫 위험 신호"},
	],
}

const SLICE_ENCOUNTERS: Array[Dictionary] = [
	{"zone": "Z01", "anchor": "spawn", "kind": "resource", "ref": "bandage", "minute": 0.5},
	{"zone": "Z01", "anchor": "spawn", "kind": "resource", "ref": "fiber", "minute": 1.0},
	{"zone": "Z01", "anchor": "S01", "kind": "trace", "ref": "crash_debris", "minute": 1.5},
	{"zone": "Z01", "anchor": "spawn", "kind": "resource", "ref": "wood", "minute": 2.0},
	{"zone": "Z01", "anchor": "S02", "kind": "landmark", "ref": "campfire_shelter", "minute": 3.0},
	{"zone": "Z01", "anchor": "outer_low", "kind": "danger", "ref": "raptor_patrol_sign", "minute": 4.0},
	{"zone": "Z02", "anchor": "S03", "kind": "landmark", "ref": "reed_pool", "minute": 4.5},
	{"zone": "Z02", "anchor": "S03", "kind": "resource", "ref": "fiber", "minute": 5.0},
	{"zone": "Z02", "anchor": "R1", "kind": "trace", "ref": "footprints", "minute": 5.5},
	{"zone": "Z02", "anchor": "S04", "kind": "landmark", "ref": "flooded_station", "minute": 6.0},
	{"zone": "Z02", "anchor": "R1", "kind": "resource", "ref": "stone", "minute": 6.5},
	{"zone": "Z02", "anchor": "S06", "kind": "danger", "ref": "raptor_crossing", "minute": 7.0},
	{"zone": "Z03", "anchor": "S06", "kind": "landmark", "ref": "echo_cave", "minute": 7.5},
	{"zone": "Z03", "anchor": "S05", "kind": "trace", "ref": "noisy_bush", "minute": 8.0},
	{"zone": "Z03", "anchor": "S05", "kind": "resource", "ref": "wood", "minute": 8.5},
	{"zone": "Z03", "anchor": "S07", "kind": "trace", "ref": "bones", "minute": 9.0},
	{"zone": "Z03", "anchor": "R2", "kind": "resource", "ref": "fiber", "minute": 9.5},
	{"zone": "Z03", "anchor": "outer_low", "kind": "danger", "ref": "raptor_patrol", "minute": 10.0},
]

## 첫 낮에는 Z01 낮은 외곽만 배회한다. 조사/추격은 감각 단서에 의해 이 반경을
## 벗어날 수 있어 기존 밤·2일차 압박과 하네스의 원인-결과를 훼손하지 않는다.
const RAPTOR_DAY_ONE_PATROL: Dictionary = {
	"zone": "Z01", "ring_min_px": 360.0, "ring_max_px": 720.0,
	"minimum_safe_distance_from_spawn_px": 360.0,
}

var _chunk_zone_cache: Dictionary = {}


func _ready() -> void:
	var ground: TileMapLayer = $Ground
	var collision: TileMapLayer = $Collision
	var boundary: TileMapLayer = $SliceBoundary
	ground.position = MAP_PIXEL_OFFSET
	collision.position = MAP_PIXEL_OFFSET
	boundary.position = MAP_PIXEL_OFFSET
	$Occlusion.position = MAP_PIXEL_OFFSET
	$Landmarks.position = MAP_PIXEL_OFFSET

	_paint_chunks(ground, collision)
	_paint_slice_boundaries(boundary)
	_bake_navigation(ground)


# --- 청크 배치 ---------------------------------------------------------------

func _paint_chunks(ground: TileMapLayer, collision: TileMapLayer) -> void:
	for row: int in range(GRID):
		for col: int in range(GRID):
			var label: String = DOC_GRID[row][col]
			# 배치도 행 0 = y7. Godot 타일 행(위=0)은 그대로 row 다.
			var cell_origin: Vector2i = Vector2i(col * TILES_PER_CHUNK, row * TILES_PER_CHUNK)
			if label == "··":
				_paint_nonplay_chunk(collision, cell_origin, nonplay_tile_for(col, row))
			else:
				_paint_zone_chunk(ground, cell_origin, label.substr(0, 1))


## 플레이 청크: Zone 변형을 셀 시드로 분산 배치한다 (반복감 감소, 결정적).
func _paint_zone_chunk(layer: TileMapLayer, cell_origin: Vector2i, zone_digit: String) -> void:
	var variants: Array = ZONE_VARIANTS[zone_digit]
	for dy: int in range(TILES_PER_CHUNK):
		for dx: int in range(TILES_PER_CHUNK):
			var cell: Vector2i = cell_origin + Vector2i(dx, dy)
			layer.set_cell(cell, SOURCE_ID, variants[variant_index(cell, variants.size())])


## 비플레이 청크: 단일 지형(절벽 또는 깊은 물). 충돌은 타일셋 물리 폴리곤이 제공한다.
func _paint_nonplay_chunk(layer: TileMapLayer, cell_origin: Vector2i, atlas: Vector2i) -> void:
	for dy: int in range(TILES_PER_CHUNK):
		for dx: int in range(TILES_PER_CHUNK):
			layer.set_cell(cell_origin + Vector2i(dx, dy), SOURCE_ID, atlas)


## Z04/Z05 전체를 지우거나 벽으로 채우지 않고, 열린 절편과 맞닿은 seam에만
## 2타일 폭 자연 장애물을 둔다. 따라서 경계 너머 지형/랜드마크는 계속 보인다.
func _paint_slice_boundaries(layer: TileMapLayer) -> void:
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	for row: int in range(GRID):
		for col: int in range(GRID):
			var locked_digit := _zone_digit_at(col, row)
			if locked_digit not in ["4", "5"]:
				continue
			for direction: Vector2i in directions:
				var open_digit := _zone_digit_at(col + direction.x, row + direction.y)
				if open_digit not in ["1", "2", "3"]:
					continue
				var atlas := TILE_CLIFF
				if locked_digit == "4":
					atlas = TILE_WATER if open_digit == "2" else Vector2i(5, 2)
				_paint_boundary_edge(layer, Vector2i(col, row), direction, atlas)


func _paint_boundary_edge(layer: TileMapLayer, chunk: Vector2i, toward_open: Vector2i,
		atlas: Vector2i) -> void:
	var origin := chunk * TILES_PER_CHUNK
	for along: int in range(TILES_PER_CHUNK):
		for depth: int in range(2):
			var cell: Vector2i
			if toward_open.x != 0:
				var x := depth if toward_open.x < 0 else TILES_PER_CHUNK - 1 - depth
				cell = origin + Vector2i(x, along)
			else:
				var y := depth if toward_open.y < 0 else TILES_PER_CHUNK - 1 - depth
				cell = origin + Vector2i(along, y)
			layer.set_cell(cell, SOURCE_ID, atlas)


## 셀 좌표 + 고정 밸리 시드의 결정적 해시 → 변형 인덱스. Godot 버전·실행과 무관하게
## 같은 셀은 항상 같은 변형이라 하네스 결정성을 깨지 않는다 (자체 정수 해시).
static func variant_index(cell: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ VALLEY_SEED
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h) % count


## 비플레이 지형 선택: 강변(Z02)에 접했거나 남쪽 저지대면 깊은 물, 그 외는 절벽.
static func nonplay_tile_for(col: int, row: int) -> Vector2i:
	for neighbor: Vector2i in [
		Vector2i(col + 1, row), Vector2i(col - 1, row),
		Vector2i(col, row + 1), Vector2i(col, row - 1),
	]:
		if _zone_digit_at(neighbor.x, neighbor.y) == "2":
			return TILE_WATER
	if row == GRID - 1:  # 남쪽 추락 접근면 저지대
		return TILE_WATER
	return TILE_CLIFF


## 격자 (col,row) 의 Zone 숫자. 범위 밖·비플레이면 빈 문자열.
static func _zone_digit_at(col: int, row: int) -> String:
	if col < 0 or col >= GRID or row < 0 or row >= GRID:
		return ""
	var label: String = DOC_GRID[row][col]
	return "" if label == "··" else label.substr(0, 1)


## 배치도 청크 좌표(dcx, dcy) → 그 청크의 좌상단 타일 셀.
static func chunk_cell_origin(doc_coord: Vector2i) -> Vector2i:
	# 배치도 dcy0(남/아래)이 Godot 타일 행 7(아래)이다 → 타일 행 = 7 - dcy.
	var tile_row: int = (GRID - 1) - doc_coord.y
	return Vector2i(doc_coord.x * TILES_PER_CHUNK, tile_row * TILES_PER_CHUNK)


## 랜드마크의 월드 좌표(오프셋 포함). 청크 중앙 셀 기준.
func landmark_world_position(landmark_id: String) -> Vector2:
	var doc_coord: Vector2i = LANDMARKS[landmark_id]
	var center_cell: Vector2i = chunk_cell_origin(doc_coord) + Vector2i(TILES_PER_CHUNK / 2, TILES_PER_CHUNK / 2)
	return MAP_PIXEL_OFFSET + ($Ground as TileMapLayer).map_to_local(center_cell)


# --- 내비게이션 --------------------------------------------------------------

## 플레이 가능한 셀 전체의 월드 AABB 를 덮는 사각형 내비게이션. 회색 상자에선 이걸로
## 충분하다 — 충돌 타일(비플레이)이 물리적으로 막으므로 경로는 벽에서 끊긴다.
func _bake_navigation(ground: TileMapLayer) -> void:
	var region: NavigationRegion2D = $NavigationRegion2D
	var min_pos: Vector2 = Vector2.INF
	var max_pos: Vector2 = -Vector2.INF
	for row: int in range(GRID):
		for col: int in range(GRID):
			if DOC_GRID[row][col] == "··":
				continue
			for corner: Vector2i in [
				Vector2i(col, row) * TILES_PER_CHUNK,
				Vector2i(col, row) * TILES_PER_CHUNK + Vector2i(TILES_PER_CHUNK - 1, TILES_PER_CHUNK - 1),
				Vector2i(col * TILES_PER_CHUNK + TILES_PER_CHUNK - 1, row * TILES_PER_CHUNK),
				Vector2i(col * TILES_PER_CHUNK, row * TILES_PER_CHUNK + TILES_PER_CHUNK - 1),
			]:
				var world: Vector2 = MAP_PIXEL_OFFSET + ground.map_to_local(corner)
				min_pos = min_pos.min(world)
				max_pos = max_pos.max(world)

	# 정점·폴리곤을 직접 세운다 (deprecated make_polygons_from_outlines 회피).
	# 회색 상자 내비는 사각형 하나면 충분하다 — test_world.tscn 과 같은 방식이다.
	var poly := NavigationPolygon.new()
	poly.vertices = PackedVector2Array([
		Vector2(min_pos.x, min_pos.y), Vector2(max_pos.x, min_pos.y),
		Vector2(max_pos.x, max_pos.y), Vector2(min_pos.x, max_pos.y),
	])
	poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = poly


# --- 조회 (테스트용) ---------------------------------------------------------

## 월드 좌표가 어느 Zone 위인가. 플레이 불가면 빈 문자열.
func zone_at_world(world_pos: Vector2) -> String:
	var cell: Vector2i = ($Ground as TileMapLayer).local_to_map(world_pos - MAP_PIXEL_OFFSET)
	var col: int = cell.x / TILES_PER_CHUNK
	var row: int = cell.y / TILES_PER_CHUNK
	if col < 0 or col >= GRID or row < 0 or row >= GRID:
		return ""
	var label: String = DOC_GRID[row][col]
	if label == "··":
		return ""
	return "Z0%s" % label.substr(0, 1)


## 플레이 가능한 청크 수 (검산용).
func playable_chunk_count() -> int:
	var count: int = 0
	for row: int in range(GRID):
		for col: int in range(GRID):
			if DOC_GRID[row][col] != "··":
				count += 1
	return count


func slice_interaction_count(zone: String) -> int:
	var count: int = 0
	for encounter: Dictionary in SLICE_ENCOUNTERS:
		if encounter.zone == zone:
			count += 1
	return count


func is_slice_zone(zone: String) -> bool:
	return zone in SLICE_ZONES

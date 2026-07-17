class_name ValleyMap
extends Node2D

## 40청크 계곡 회색 상자 (MAP_DESIGN_DRAFT §2/§3, 정본 §7~§10).
##
## 8×8 청크(각 32×32 아이소메트릭 64×32px 타일). 40개는 플레이 가능(Zone별 색),
## 나머지는 비플레이(절벽/물, 충돌). 청크·랜드마크·충돌·내비게이션을 _ready 에서
## 프로그램으로 칠한다 — 40960+ 타일을 씬에 굽지 않는다 (§8.6: 회색 상자 먼저).
##
## 좌표 계약(★ 하네스·게임플레이 좌표 불변): main.tscn 의 Player(-384,200)·사체·
## 캠프파이어·LoopObjective(640,700)·랩터 좌표는 바뀌지 않는다. 대신 이 맵을
## MAP_PIXEL_OFFSET 만큼 밀어 Z01(시작 지역)이 그 좌표들을 덮게 한다.
## tests/world/test_valley_map.gd 가 이 불변식을 지킨다.

const TILES_PER_CHUNK: int = 32
const GRID: int = 8

## 아틀라스 타일 인덱스 (valley_tileset.tres 순서).
const TILE_Z01: int = 0
const TILE_Z02: int = 1
const TILE_Z03: int = 2
const TILE_Z04: int = 3
const TILE_Z05: int = 4
const TILE_NONPLAY: int = 5
const SOURCE_ID: int = 0

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

var _chunk_zone_cache: Dictionary = {}


func _ready() -> void:
	var ground: TileMapLayer = $Ground
	var collision: TileMapLayer = $Collision
	ground.position = MAP_PIXEL_OFFSET
	collision.position = MAP_PIXEL_OFFSET
	$Occlusion.position = MAP_PIXEL_OFFSET
	$Landmarks.position = MAP_PIXEL_OFFSET

	_paint_chunks(ground, collision)
	_place_landmarks(ground)
	_bake_navigation(ground)


# --- 청크 배치 ---------------------------------------------------------------

func _paint_chunks(ground: TileMapLayer, collision: TileMapLayer) -> void:
	for row: int in range(GRID):
		for col: int in range(GRID):
			var label: String = DOC_GRID[row][col]
			# 배치도 행 0 = y7. Godot 타일 행(위=0)은 그대로 row 다.
			var cell_origin: Vector2i = Vector2i(col * TILES_PER_CHUNK, row * TILES_PER_CHUNK)
			if label == "··":
				_paint_chunk_cells(collision, cell_origin, TILE_NONPLAY)
			else:
				_paint_chunk_cells(ground, cell_origin, zone_tile_for(label))


func _paint_chunk_cells(layer: TileMapLayer, cell_origin: Vector2i, tile_index: int) -> void:
	var atlas: Vector2i = Vector2i(tile_index, 0)
	for dy: int in range(TILES_PER_CHUNK):
		for dx: int in range(TILES_PER_CHUNK):
			layer.set_cell(cell_origin + Vector2i(dx, dy), SOURCE_ID, atlas)


## 청크 라벨 앞 숫자가 Zone 이다 (1→Z01 …). 반환은 아틀라스 타일 인덱스.
static func zone_tile_for(label: String) -> int:
	match label.substr(0, 1):
		"1": return TILE_Z01
		"2": return TILE_Z02
		"3": return TILE_Z03
		"4": return TILE_Z04
		"5": return TILE_Z05
		_: return TILE_NONPLAY


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


# --- 랜드마크 마커 -----------------------------------------------------------

func _place_landmarks(ground: TileMapLayer) -> void:
	var container: Node2D = $Landmarks
	for landmark_id: String in LANDMARKS:
		var doc_coord: Vector2i = LANDMARKS[landmark_id]
		var center_cell: Vector2i = chunk_cell_origin(doc_coord) + Vector2i(TILES_PER_CHUNK / 2, TILES_PER_CHUNK / 2)
		var marker: Node2D = _make_marker(landmark_id)
		marker.name = landmark_id
		marker.position = ground.map_to_local(center_cell)
		container.add_child(marker)


## 회색 상자 마커: 단순 마름모 + 라벨. 기능은 범위 밖 (위치·이름만).
func _make_marker(landmark_id: String) -> Node2D:
	var marker := Node2D.new()
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([
		Vector2(0, -14), Vector2(20, 0), Vector2(0, 14), Vector2(-20, 0),
	])
	# 랜드마크 종류별 색: S=주 앵커(밝은 호박), F=모닥불(주황), R=경로(청록), H=해체(적갈).
	var kind: String = landmark_id.substr(0, 1)
	diamond.color = {
		"S": Color(0.88, 0.64, 0.35, 0.92), "F": Color(0.90, 0.50, 0.25, 0.9),
		"R": Color(0.44, 0.72, 0.72, 0.9), "H": Color(0.66, 0.26, 0.22, 0.9),
	}.get(kind, Color(0.8, 0.8, 0.8, 0.9))
	diamond.z_index = 30
	marker.add_child(diamond)

	var label := Label.new()
	label.text = LANDMARK_LABELS.get(landmark_id, landmark_id)
	label.position = Vector2(-24, -34)
	label.add_theme_font_size_override(&"font_size", 11)
	label.z_index = 31
	marker.add_child(label)
	return marker


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

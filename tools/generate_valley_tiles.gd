extends SceneTree

## ⚠️ DEPRECATED — 대체됨 (연결 TA). 더 이상 빌드/런타임에 쓰이지 않는다.
##
## 이 스크립트는 회색 상자 단계의 프로그램 생성 아틀라스(valley_tiles.png, 단색 다이아몬드
## 6종)를 만들었다. 이제 정식 지형 시트 assets/tiles/valley_terrain_tiles_sheet.png(17종)로
## 교체됐고, valley_tileset.tres 와 valley_map.gd 는 그 시트를 참조한다.
## 산출물 valley_tiles.png(+.import)는 삭제됐다. 이 스크립트를 실행하면 죽은 아틀라스가
## 다시 생기므로 실행하지 말 것. 회색 상자 재현이 필요할 때의 기록으로만 남긴다.
##
## --- 아래는 원래 회색 상자 생성기 (역사적 기록) ---
##
## 회색 상자 계곡 타일 아틀라스 생성기 (레인 M, 에셋 정책: 새 아트 생성 불가 →
## 저채도 자연색으로 프로그램 생성). 07-16 '임시에셋 스타일 가이드' 팔레트 기반.
## 산출: assets/tiles/valley_tiles.png — 64×32 아이소메트릭 다이아몬드 6종.
##   0 Z01 추락 분지(회갈)  1 Z02 갈대 강변(청록끼 습지)  2 Z03 메아리 밀림(짙은 녹)
##   3 Z04 둥지 평원(마른 풀)  4 Z05 검은 능선(검은 암반)  5 비플레이(절벽/물, 충돌)

const TILE_W: int = 64
const TILE_H: int = 32
const TILE_COUNT: int = 6
const OUT_PATH: String = "res://assets/tiles/valley_tiles.png"

## Zone 색 (저채도 자연색). 각각 [면색, 테두리색].
const ZONE_COLORS: Array = [
	[Color8(107, 97, 79), Color8(84, 74, 58)],     # Z01 회갈 (분지)
	[Color8(72, 108, 108), Color8(52, 82, 82)],    # Z02 청록끼 습지 (강변)
	[Color8(56, 86, 56), Color8(38, 62, 38)],      # Z03 짙은 녹 (밀림)
	[Color8(140, 132, 86), Color8(108, 100, 62)],  # Z04 마른 풀 (평원)
	[Color8(51, 51, 59), Color8(33, 33, 41)],      # Z05 검은 암반 (능선)
	[Color8(30, 40, 56), Color8(18, 24, 36)],      # 비플레이 절벽/물 (충돌)
]


func _init() -> void:
	var image: Image = Image.create(TILE_W * TILE_COUNT, TILE_H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for tile_index: int in range(TILE_COUNT):
		_draw_diamond(image, tile_index * TILE_W, ZONE_COLORS[tile_index][0], ZONE_COLORS[tile_index][1])

	var error: int = image.save_png(OUT_PATH)
	if error != OK:
		printerr("valley_tiles.png 저장 실패: %d" % error)
		quit(1)
		return
	print("생성: %s (%d×%d, %d 타일)" % [OUT_PATH, image.get_width(), image.get_height(), TILE_COUNT])
	quit(0)


## 64×32 다이아몬드를 칠한다. 꼭짓점: 위(32,0) 오른쪽(63,16) 아래(32,31) 왼쪽(0,16).
## 각 행에서 다이아몬드 폭 안쪽만 채우고, 가장자리 1px 은 테두리색으로 둔다.
func _draw_diamond(image: Image, x_offset: int, fill: Color, edge: Color) -> void:
	for y: int in range(TILE_H):
		# 중심 y=15.5 기준 다이아몬드 반폭. 위/아래 꼭짓점에서 0, 중앙에서 최대 32.
		var dy: float = absf(float(y) - 15.5)
		var half_width: int = int(round((1.0 - dy / 16.0) * 32.0))
		if half_width <= 0:
			continue
		var center_x: int = 32
		for dx: int in range(-half_width, half_width):
			var px: int = x_offset + center_x + dx
			# 가장자리(다이아몬드 경계 1칸)는 테두리색.
			var is_edge: bool = dx <= -half_width + 1 or dx >= half_width - 2
			image.set_pixel(px, y, edge if is_edge else fill)

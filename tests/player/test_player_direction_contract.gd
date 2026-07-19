extends GutTest

const SHEET_PATH := "res://assets/sprites/player/player_survivor_sheet.png"
const CELL_W := 48
const CELL_H := 64
const D_N := 0
const D_E := 2
const D_SE := 3
const D_S := 4
const D_SW := 5
const D_W := 6


## 방향 열은 이동 벡터와 직접 대응한다. legacy 회화풍 시트는 고정 좌표 검증이
## 취약하므로 ①E/W·SE/SW 미러 구조 보장 ②판별 행(1,2,4,5)의 얼굴 분포
## ③S/N 얼굴 노출 비대칭 ④S 눈 존재로 계약을 고정한다.
func test_direction_columns_keep_face_orientation_contract() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SHEET_PATH))
	image.convert(Image.FORMAT_RGBA8)

	# ① 미러 구조: E == flip(W), SE == flip(SW) — 좌우 스왑 회귀를 픽셀로 차단
	for row: int in range(6):
		assert_true(_cells_mirror(image, D_E, D_W, row), "row %d: E는 W의 미러" % row)
		assert_true(_cells_mirror(image, D_SE, D_SW, row), "row %d: SE는 SW의 미러" % row)

	# ② 판별 행에서 E 얼굴은 오른쪽, W 얼굴은 왼쪽에 몰린다
	for row: int in [1, 2, 4, 5]:
		var east := _head_skin_xs(image, D_E, row)
		var west := _head_skin_xs(image, D_W, row)
		assert_gt(east.size(), 4, "row %d E 얼굴 표본" % row)
		assert_gte(_percentile(east, 0.25), 24.0, "row %d E 얼굴은 오른쪽" % row)
		assert_lte(_percentile(west, 0.75), 23.0, "row %d W 얼굴은 왼쪽" % row)

	# ③ 정면은 얼굴 노출, 후면은 뒤통수
	for row: int in range(6):
		var south := _head_skin_xs(image, D_S, row)
		var north := _head_skin_xs(image, D_N, row)
		assert_gt(south.size(), north.size() * 2,
			"row %d: S 얼굴 피부가 N의 2배 초과" % row)

	# ④ S 얼굴에 눈(스킨 인접 다크 픽셀)이 있다
	for row: int in range(6):
		assert_true(_has_eye_pixels(image, D_S, row), "row %d: S 눈 존재" % row)


func _cells_mirror(image: Image, dir_a: int, dir_b: int, row: int) -> bool:
	# 실루엣(알파)만 미러 동일성을 요구한다 — 색은 광원 방향 일관성(좌상단)을
	# 위해 미러 후에도 다시 칠해지므로 좌우가 같을 수 없다.
	for y: int in range(CELL_H):
		for x: int in range(CELL_W):
			var a := image.get_pixel(dir_a * CELL_W + x, row * CELL_H + y).a > 0.0
			var b := image.get_pixel(
				dir_b * CELL_W + (CELL_W - 1 - x), row * CELL_H + y).a > 0.0
			if a != b:
				return false
	return true


func _head_skin_xs(image: Image, direction: int, row: int) -> Array[float]:
	var xs: Array[float] = []
	for y: int in range(8, 20):
		for x: int in range(12, 36):
			var color := image.get_pixel(direction * CELL_W + x, row * CELL_H + y)
			if color.a > 0.0 and color.r > 0.45 and color.g > 0.22 \
					and color.r > color.b * 1.25:
				xs.append(float(x))
	xs.sort()
	return xs


func _percentile(sorted_xs: Array[float], q: float) -> float:
	if sorted_xs.is_empty():
		return -1.0
	return sorted_xs[int(float(sorted_xs.size() - 1) * q)]


func _has_eye_pixels(image: Image, direction: int, row: int) -> bool:
	var count := 0
	for y: int in range(13, 21):
		for x: int in range(14, 34):
			var color := image.get_pixel(direction * CELL_W + x, row * CELL_H + y)
			if color.a > 0.0 and color.get_luminance() < 0.2:
				var left := image.get_pixel(direction * CELL_W + x - 1, row * CELL_H + y)
				var right := image.get_pixel(direction * CELL_W + x + 1, row * CELL_H + y)
				for side: Color in [left, right]:
					if side.a > 0.0 and side.r > 0.45 and side.r > side.b * 1.25:
						count += 1
						break
	return count >= 2

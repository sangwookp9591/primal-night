extends GutTest

const SHEET_PATH := "res://assets/sprites/player/player_survivor_sheet.png"
const CELL_WIDTH := 48
const CELL_HEIGHT := 64
const HEAD_RECT := Rect2i(14, 7, 21, 20)
const DIRECTION_N := 0
const DIRECTION_E := 2
const DIRECTION_S := 4
const DIRECTION_W := 6


## 방향 열은 이동 벡터와 직접 대응한다. 특히 프로필을 좌우 반대로 그리면
## 애니메이션 자체는 정상이어도 E/W 이동 중 캐릭터가 문워크하므로 피부 무게중심으로
## 얼굴이 열린 쪽을 고정한다.
func test_idle_direction_columns_keep_face_orientation_contract() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SHEET_PATH))
	image.convert(Image.FORMAT_RGBA8)

	var north := _head_skin_points(image, DIRECTION_N)
	var south := _head_skin_points(image, DIRECTION_S)
	var east := _head_skin_points(image, DIRECTION_E)
	var west := _head_skin_points(image, DIRECTION_W)

	assert_gt(south.size(), 70, "S 열은 눈·입을 둘 충분한 정면 얼굴 피부를 노출한다")
	assert_lt(north.size(), south.size() / 4, "N 열은 S 열보다 얼굴 피부가 대폭 적어야 한다")
	assert_true(_has_dark_eye_pixels(image, DIRECTION_S), "S 열 정면 얼굴에는 두 눈이 있어야 한다")

	var east_centroid := _mean_x(east)
	var west_centroid := _mean_x(west)
	assert_gt(east_centroid, 26.0, "E 열 얼굴은 셀 중심 오른쪽으로 열려야 한다")
	assert_lt(west_centroid, 22.0, "W 열 얼굴은 셀 중심 왼쪽으로 열려야 한다")
	assert_gt(east_centroid - west_centroid, 7.0,
		"E/W 얼굴 무게중심은 좌우 프로필로 유의미하게 분리되어야 한다")


func _head_skin_points(image: Image, direction: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for y: int in range(HEAD_RECT.position.y, HEAD_RECT.end.y):
		for x: int in range(HEAD_RECT.position.x, HEAD_RECT.end.x):
			var color := image.get_pixel(direction * CELL_WIDTH + x, y)
			if color.a > 0.0 and color.r > 0.45 and color.g > 0.22 \
					and color.r > color.b * 1.25:
				points.append(Vector2i(x, y))
	return points


func _mean_x(points: Array[Vector2i]) -> float:
	assert_gt(points.size(), 0, "프로필 얼굴 피부 표본이 있어야 한다")
	var total := 0.0
	for point: Vector2i in points:
		total += float(point.x)
	return total / float(points.size())


func _has_dark_eye_pixels(image: Image, direction: int) -> bool:
	var dark_count := 0
	for y: int in range(17, 22):
		for x: int in range(17, 31):
			var color := image.get_pixel(direction * CELL_WIDTH + x, y)
			if color.a > 0.0 and color.get_luminance() < 0.22:
				dark_count += 1
	return dark_count >= 4

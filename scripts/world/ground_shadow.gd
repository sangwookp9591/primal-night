class_name GroundShadow
extends Node2D

## 발밑 소프트 그림자 공용 구현. 톤·겹 구조는 여기 한 곳만 소유하고,
## 씬은 radius(타원 반경)만 지정한다 — 씬별 손좌표 복제를 없앤다.

const SOFT_COLOR := Color(0.035, 0.045, 0.04, 0.075)
const CORE_COLOR := Color(0.02, 0.025, 0.022, 0.14)
const CORE_RATIO: float = 0.8
const POINT_COUNT: int = 16

@export var radius: Vector2 = Vector2(20.0, 6.0)


func _ready() -> void:
	z_index = -10
	_add_layer(&"SoftEdge", radius, SOFT_COLOR)
	_add_layer(&"Core", radius * CORE_RATIO, CORE_COLOR)


func _add_layer(layer_name: StringName, layer_radius: Vector2, color: Color) -> void:
	if get_node_or_null(NodePath(layer_name)) != null:
		return
	var polygon := Polygon2D.new()
	polygon.name = layer_name
	polygon.polygon = _ellipse_points(layer_radius)
	polygon.color = color
	add_child(polygon)


static func _ellipse_points(ellipse_radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in range(POINT_COUNT):
		var angle := TAU * float(index) / float(POINT_COUNT)
		points.append(Vector2(cos(angle) * ellipse_radius.x, sin(angle) * ellipse_radius.y))
	return points

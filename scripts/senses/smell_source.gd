class_name SmellSource
extends Node2D

## 등록형 냄새 원천. SmellGrid 가 틱마다 등록 목록만 훑는다.

@export var kind: StringName = &"raw_meat"
@export var strength: float = 45.0
@export var interval_seconds: float = 0.5

var _grid: SmellGrid = null

func _ready() -> void:
	_grid = SmellGrid.find_in(get_tree())
	if _grid != null:
		_grid.register_smell_source(self, Callable(self, "get_smell_position"),
			strength, interval_seconds, kind)

func _exit_tree() -> void:
	deactivate()

func deactivate() -> void:
	if _grid != null:
		_grid.unregister_smell_source(self)
		_grid = null

func get_smell_position() -> Vector2:
	return global_position

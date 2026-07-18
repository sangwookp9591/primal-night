class_name SmellSource
extends Node2D

## 등록형 냄새 원천. SmellGrid 가 틱마다 등록 목록만 훑는다.

@export var kind: StringName = &"raw_meat"
@export var strength: float = 45.0
@export var interval_seconds: float = 0.5

var _grid: SmellGrid = null
## 등록되기 전에 해제됐는가. 지연 등록이 뒤늦게 되살리는 것을 막는다.
var _released: bool = false

func _ready() -> void:
	# ★ 등록을 한 프레임 미룬다. SmellGrid 는 자기 _ready 에서 smell_grid 그룹에
	# 가입하는데, main.tscn 은 SurvivalDemo(바닥 아이템)를 SmellGrid 앞에 둔다.
	# 여기서 곧장 찾으면 그룹이 아직 비어 있어 조용히 등록에 실패한다 — 실제로
	# W3-T4 이후 바닥 raw_meat 이 실기에서 냄새를 낸 적이 없었다.
	# 씬의 노드 순서에 기대지 않으려면 모든 _ready 가 끝난 뒤에 찾아야 한다.
	# (같은 이유로 scripts/world/carcass.gd 도 등록을 미룬다.)
	_register.call_deferred()

func _register() -> void:
	# 지연되는 사이에 주워지거나(WorldItem.apply_pickup) 트리에서 빠질 수 있다.
	if _released or _grid != null or not is_inside_tree():
		return
	_grid = SmellGrid.find_in(get_tree())
	if _grid != null:
		_grid.register_smell_source(self, Callable(self, "get_smell_position"),
			strength, interval_seconds, kind)

func _exit_tree() -> void:
	deactivate()

func deactivate() -> void:
	_released = true
	if _grid != null:
		_grid.unregister_smell_source(self)
		_grid = null

func reactivate() -> void:
	_released = false
	_register.call_deferred()

func get_smell_position() -> Vector2:
	return global_position

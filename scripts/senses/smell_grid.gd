class_name SmellGrid
extends Node2D

## 저해상도 냄새 격자 (설계서 5.4 / 성능문서 5.2).
## EventBus.smell_emitted 를 받아 셀에 쌓고, 바람 방향으로 이동(advect)하며
## 시간에 따라 감소(decay)한다.
## - 갱신은 tick_interval 주기로만 (기본 초당 4회). 매 프레임 전체 순회 금지.
## - 활성 셀만 처리한다. 격자 배열은 _ready 에서 1회 할당해 재사용한다.

const DEFAULT_CONFIG: SmellGridConfig = preload("res://data/creatures/smell_grid_config.tres")

@export var config: SmellGridConfig = DEFAULT_CONFIG
## 격자가 덮는 월드 영역. 맵 배치 값이므로 씬에서 지정한다 (기본값은 test_world 의 nav 영역).
@export var area_origin: Vector2 = Vector2(-1280.0, -64.0)
@export var area_size: Vector2 = Vector2(2560.0, 1472.0)

## 바람은 월드 상태다. 씬에서 초기값을 주고 디버그에서 바꿀 수 있다 (설계서 5.4).
@export var wind_direction: Vector2 = Vector2.ZERO
@export var wind_strength: float = 1.0

var _cols: int = 0
var _rows: int = 0
var _values: PackedFloat32Array = PackedFloat32Array()
var _active: Dictionary = {}
var _tick_elapsed: float = 0.0
var _perf: Node = null

## 틱 중 재사용하는 스냅샷 버퍼 (매 틱 신규 배열 할당 금지, 성능문서 6.1).
var _snapshot_indices: PackedInt32Array = PackedInt32Array()
var _snapshot_values: PackedFloat32Array = PackedFloat32Array()

## 디버그 시각화 (설계서 5.4 / 13장). 출시 빌드에서는 켤 수 없다.
var debug_enabled: bool = false

func _ready() -> void:
	add_to_group(&"smell_grid")
	_cols = maxi(int(ceilf(area_size.x / config.cell_size)), 1)
	_rows = maxi(int(ceilf(area_size.y / config.cell_size)), 1)
	_values.resize(_cols * _rows)
	if has_node("/root/PerfMonitor"):
		_perf = get_node("/root/PerfMonitor")
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").smell_emitted.connect(_on_smell_emitted)

func _process(delta: float) -> void:
	_tick_elapsed += delta
	while _tick_elapsed >= config.tick_interval:
		_tick_elapsed -= config.tick_interval
		if _perf != null:
			_perf.begin_sample(&"scent")
		_tick()
		if _perf != null:
			_perf.end_sample(&"scent")
		if debug_enabled:
			queue_redraw()

## 디버그 조작. 입력 맵(project.godot)은 소유 밖이라 키를 직접 본다.
## F4: 시각화 토글, F6: 바람 방향 45도 회전, F7: 바람 세기 순환 (1 → 0 → 0.5).
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_F4:
			debug_enabled = not debug_enabled
			queue_redraw()
		KEY_F6:
			if wind_direction.is_zero_approx():
				wind_direction = Vector2.RIGHT
			else:
				wind_direction = wind_direction.rotated(TAU / 8.0)
			queue_redraw()
		KEY_F7:
			if wind_strength >= 0.75:
				wind_strength = 0.0
			elif wind_strength < 0.25:
				wind_strength = 0.5
			else:
				wind_strength = 1.0
			queue_redraw()

func _draw() -> void:
	if not debug_enabled:
		return
	# 활성 셀 농도 (붉은 사각형, 알파 = 농도).
	var cell: float = config.cell_size
	for cell_index: int in _active:
		var cell_x: int = cell_index % _cols
		var cell_y: int = cell_index / _cols
		var alpha: float = clampf(_values[cell_index] / 60.0, 0.05, 0.6)
		var top_left: Vector2 = to_local(area_origin + Vector2(float(cell_x) * cell, float(cell_y) * cell))
		draw_rect(Rect2(top_left, Vector2(cell, cell)), Color(0.9, 0.1, 0.1, alpha))
		draw_rect(Rect2(top_left, Vector2(cell, cell)), Color(0.9, 0.3, 0.2, 0.8), false, 1.0)
	# 바람 화살표 (격자 원점 부근).
	if not wind_direction.is_zero_approx() and wind_strength > 0.0:
		var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
		var anchor: Vector2 = to_local(player.global_position + Vector2(0.0, -96.0)) if player != null else to_local(area_origin)
		var tip: Vector2 = anchor + wind_direction.normalized() * 48.0 * wind_strength
		draw_line(anchor, tip, Color.CYAN, 2.0)
		draw_circle(tip, 4.0, Color.CYAN)

func get_smell_at(global_pos: Vector2) -> float:
	var index: int = _cell_index(global_pos)
	if index < 0:
		return 0.0
	return _values[index]

## 농도가 증가하는 방향 (경사 추적). 랩터는 좌표가 아니라 이 경사를 따라간다.
func get_gradient_direction(global_pos: Vector2) -> Vector2:
	var index: int = _cell_index(global_pos)
	if index < 0:
		return Vector2.ZERO

	var own_value: float = _values[index]
	var cell_x: int = index % _cols
	var cell_y: int = index / _cols
	var best_value: float = own_value
	var best_direction: Vector2 = Vector2.ZERO
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			var neighbor_x: int = cell_x + offset_x
			var neighbor_y: int = cell_y + offset_y
			if neighbor_x < 0 or neighbor_x >= _cols or neighbor_y < 0 or neighbor_y >= _rows:
				continue
			var neighbor_value: float = _values[neighbor_y * _cols + neighbor_x]
			if neighbor_value > best_value:
				best_value = neighbor_value
				best_direction = Vector2(float(offset_x), float(offset_y))
	if best_direction == Vector2.ZERO:
		return Vector2.ZERO
	return best_direction.normalized()

func get_active_cell_count() -> int:
	return _active.size()

func _on_smell_emitted(position: Vector2, strength: float, _kind: StringName) -> void:
	var index: int = _cell_index(position)
	if index < 0 or strength <= 0.0:
		return
	_values[index] += strength
	_active[index] = true

func _cell_index(global_pos: Vector2) -> int:
	var local: Vector2 = global_pos - area_origin
	if local.x < 0.0 or local.y < 0.0 or local.x >= area_size.x or local.y >= area_size.y:
		return -1
	var cell_x: int = int(local.x / config.cell_size)
	var cell_y: int = int(local.y / config.cell_size)
	if cell_x >= _cols or cell_y >= _rows:
		return -1
	return cell_y * _cols + cell_x

## 한 틱: 활성 셀만 감쇠 + 바람 방향 이웃으로 이동. 스냅샷 값 기준 2-pass 라
## 같은 틱의 이동분이 연쇄로 다시 이동하지 않는다.
func _tick() -> void:
	var active_count: int = _active.size()
	if active_count == 0:
		return

	var wind_offset: Vector2i = Vector2i.ZERO
	var moved_fraction: float = 0.0
	if wind_strength > 0.0 and not wind_direction.is_zero_approx():
		var normalized: Vector2 = wind_direction.normalized()
		wind_offset = Vector2i(roundi(normalized.x), roundi(normalized.y))
		if wind_offset != Vector2i.ZERO:
			moved_fraction = clampf(config.advect_fraction * wind_strength, 0.0, 1.0)

	_snapshot_indices.resize(active_count)
	_snapshot_values.resize(active_count)
	var snapshot_index: int = 0
	for cell_index: int in _active:
		_snapshot_indices[snapshot_index] = cell_index
		_snapshot_values[snapshot_index] = _values[cell_index]
		snapshot_index += 1

	# pass 1: 잔류분 감쇠
	for k: int in range(active_count):
		var value: float = _snapshot_values[k]
		_values[_snapshot_indices[k]] = (value - value * moved_fraction) * config.decay_factor

	# pass 2: 이동분을 풍하 셀에 가산 (영역 밖으로 나가면 소실)
	if moved_fraction > 0.0:
		for k: int in range(active_count):
			var moved: float = _snapshot_values[k] * moved_fraction * config.decay_factor
			if moved <= 0.0:
				continue
			var cell_index: int = _snapshot_indices[k]
			var target_x: int = cell_index % _cols + wind_offset.x
			var target_y: int = cell_index / _cols + wind_offset.y
			if target_x < 0 or target_x >= _cols or target_y < 0 or target_y >= _rows:
				continue
			var target_index: int = target_y * _cols + target_x
			_values[target_index] += moved
			_active[target_index] = true

	# 약해진 셀 비활성화 (활성 셀만 갱신 유지)
	for k: int in range(active_count):
		var cell_index: int = _snapshot_indices[k]
		if _values[cell_index] < config.min_active_value:
			_values[cell_index] = 0.0
			_active.erase(cell_index)

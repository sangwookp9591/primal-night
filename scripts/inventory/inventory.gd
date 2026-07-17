class_name Inventory
extends Node

## 16칸 슬롯 + 무게 제한 인벤토리 (설계서 5.8).
##
## 불변식 (tests/inventory/test_inventory.gd 가 검증한다):
##   1. 슬롯은 slot_count 개를 넘지 않는다.
##   2. 한 슬롯의 수량은 ItemData.get_stack_limit() 을 넘지 않는다.
##   3. 수량은 음수가 되지 않는다.
##   4. 총 무게는 max_weight 를 넘지 않는다.
##
## 수량은 GameData 에 등록된 ItemData 로만 검증한다. 등록되지 않은 id 는
## 조용히 기본값으로 대체하지 않고 거부한다 (설계서 13장).

## HUD 는 이 신호로만 갱신한다. 매 프레임 폴링하지 않는다 (성능문서 6.2).
signal changed()

## 보유 냄새 원천 합산 규칙 (설계서 5.4).
##
## 여러 개를 들면 더 강한 냄새가 나야 하지만, 단순 곱셈 합산은 고기 한 스택으로
## 맵 전체를 덮어 포식자 유인이 무의미해진다. 그래서 "최댓값 + 가산" 을 쓴다:
##   가장 강한 원천 1단위가 기준(base), 나머지 각 단위는 자기 강도의
##   ADDITIONAL_UNIT_FACTOR 만큼만 더하고, 총합은 base * MAX_MULTIPLIER 에서 막는다.
## 냄새 종류/주기는 가장 강한 원천의 것을 따른다. 섞어 들면 센 쪽이 존재를 지운다.
const CARRIED_SMELL_ADDITIONAL_UNIT_FACTOR: float = 0.5
const CARRIED_SMELL_MAX_MULTIPLIER: float = 3.0

@export var slot_count: int = 16
@export var max_weight: float = 20.0

## 슬롯은 _ready 에서 한 번만 할당하고 이후에는 제자리에서 수정한다.
## 획득/소비마다 새 Dictionary 를 만들지 않는다 (성능문서 6.1).
var _slots: Array[Dictionary] = []
var _game_data: Node = null
var _carried_smell_grid: SmellGrid = null

func _ready() -> void:
	_game_data = get_node("/root/GameData")
	_slots.resize(slot_count)
	for i: int in range(slot_count):
		_slots[i] = {}

## 실제로 들어간 개수를 반환한다. 자리가 부족하면 들어간 만큼만 반환한다.
func add_item(id: StringName, count: int) -> int:
	if count <= 0:
		return 0

	var item: ItemData = _game_data.get_item(id)
	if item == null:
		return 0
	if not is_finite(item.weight) or item.weight <= 0.0:
		push_error("Inventory: invalid weight for item %s" % id)
		return 0

	var limit: int = item.get_stack_limit()
	var weight_room: int = maxi(floori((max_weight - total_weight()) / item.weight), 0)
	var allowed: int = mini(count, weight_room)
	var remaining: int = allowed

	# 1) 기존 스택을 먼저 채운다. 새 슬롯을 낭비하지 않는다.
	for slot: Dictionary in _slots:
		if remaining <= 0:
			break
		if slot.is_empty() or slot["id"] != id:
			continue
		var room: int = limit - int(slot["count"])
		if room <= 0:
			continue
		var moved: int = mini(room, remaining)
		slot["count"] = int(slot["count"]) + moved
		remaining -= moved

	# 2) 남으면 빈 슬롯에 새 스택을 만든다. 슬롯이 없으면 거기서 끝난다.
	for slot: Dictionary in _slots:
		if remaining <= 0:
			break
		if not slot.is_empty():
			continue
		var moved: int = mini(limit, remaining)
		slot["id"] = id
		slot["count"] = moved
		remaining -= moved

	var added: int = allowed - remaining
	if added > 0:
		_update_carried_smell_source(id)
		changed.emit()
	return added

## 전부 아니면 전무. 보유량이 부족하면 아무것도 건드리지 않고 false 를 반환한다.
func remove_item(id: StringName, count: int) -> bool:
	if count <= 0 or count_of(id) < count:
		return false

	var remaining: int = count
	for slot: Dictionary in _slots:
		if remaining <= 0:
			break
		if slot.is_empty() or slot["id"] != id:
			continue
		var taken: int = mini(int(slot["count"]), remaining)
		slot["count"] = int(slot["count"]) - taken
		remaining -= taken
		if int(slot["count"]) <= 0:
			slot.clear()

	changed.emit()
	_update_carried_smell_source(id)
	return true

func count_of(id: StringName) -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		if not slot.is_empty() and slot["id"] == id:
			total += int(slot["count"])
	return total

func has_item(id: StringName, count: int) -> bool:
	return count_of(id) >= count

## HUD 용 읽기 전용 조회. 비어 있으면 빈 Dictionary.
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		return {}
	return _slots[index]

func used_slots() -> int:
	var used: int = 0
	for slot: Dictionary in _slots:
		if not slot.is_empty():
			used += 1
	return used

func total_weight() -> float:
	var total: float = 0.0
	for slot: Dictionary in _slots:
		if slot.is_empty():
			continue
		var item: ItemData = _game_data.get_item(slot["id"])
		if item != null:
			total += item.weight * float(slot["count"])
	return total

## 보유 중인 모든 냄새 원천을 합산한 결과. 원천이 없으면 빈 Dictionary.
## 반환: {strength: float, interval: float, kind: StringName}
##
## 슬롯 단위가 아니라 개수 단위로 센다. 스택 상한을 넘겨 여러 슬롯에 흩어져도
## 전량이 합산에 들어간다.
func get_carried_smell() -> Dictionary:
	var strongest: ItemData = null
	var strength_sum: float = 0.0

	for slot: Dictionary in _slots:
		if slot.is_empty():
			continue
		var item: ItemData = _game_data.get_item(slot["id"])
		if item == null or not item.is_smell_source():
			continue
		strength_sum += item.smell_strength * float(slot["count"])
		if strongest == null or item.smell_strength > strongest.smell_strength:
			strongest = item

	if strongest == null:
		return {}

	var base: float = strongest.smell_strength
	# 기준 1단위는 제값을 다 내고, 나머지 단위만 가산 계수를 받는다.
	var extra: float = (strength_sum - base) * CARRIED_SMELL_ADDITIONAL_UNIT_FACTOR
	var total: float = minf(base + extra, base * CARRIED_SMELL_MAX_MULTIPLIER)

	return {
		strength = total,
		interval = strongest.smell_interval_seconds,
		kind = strongest.get_smell_kind(),
	}

## 냄새 원천 보유량이 바뀔 때마다 합산 결과로 등록을 통째로 갱신한다.
## 등록은 소유자(self) 하나로 유지한다. 격자는 owner 당 원천 하나만 들고 있다.
func _update_carried_smell_source(id: StringName) -> void:
	var changed_item: ItemData = _game_data.get_item(id)
	if changed_item == null or not changed_item.is_smell_source():
		return
	var grid: SmellGrid = _find_smell_grid()
	if grid == null:
		return
	var carried: Dictionary = get_carried_smell()
	if carried.is_empty():
		grid.unregister_smell_source(self)
		return
	grid.register_smell_source(self, Callable(self, "_carried_smell_position"),
		carried["strength"], carried["interval"], carried["kind"])

func _find_smell_grid() -> SmellGrid:
	if _carried_smell_grid == null or not is_instance_valid(_carried_smell_grid):
		_carried_smell_grid = SmellGrid.find_in(get_tree())
	return _carried_smell_grid

func _carried_smell_position() -> Vector2:
	var body: Node2D = get_parent() as Node2D
	if body == null:
		return Vector2.INF
	return body.global_position

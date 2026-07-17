class_name CraftingKnowledge
extends Node

## 플레이어별 제작 지식. 산출물 판정은 소유하지 않고 발견 상태와 관찰문만 보관한다.

signal observation_added(text: String)

const NODE_NAME: StringName = &"CraftingKnowledge"
const MAX_OBSERVATIONS: int = 32
const RECIPE_ID_MAX_LENGTH: int = 48
const OBSERVATION_MAX_LENGTH: int = 160

var _discovered: Dictionary = {}
var _observations: Array[Dictionary] = []
var _recorded_kinds: Dictionary = {}


static func ensure_on(actor: Node) -> CraftingKnowledge:
	if actor == null:
		return null
	var existing := actor.get_node_or_null(NodePath(String(NODE_NAME))) as CraftingKnowledge
	if existing != null:
		return existing
	var knowledge := CraftingKnowledge.new()
	knowledge.name = NODE_NAME
	actor.add_child(knowledge)
	return knowledge


func has_discovered(recipe_id: StringName) -> bool:
	return _discovered.has(recipe_id)


func discovered_recipe_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for recipe_id: StringName in _discovered:
		ids.append(recipe_id)
	ids.sort()
	return ids


func observations() -> Array[Dictionary]:
	return _observations.duplicate(true)


## 호스트 확정 또는 호스트 스냅샷 적용 경계에서만 호출한다.
func apply_observation(recipe_id: StringName, kind: StringName, text: String,
		session_time: float, notify: bool = true) -> bool:
	if recipe_id.is_empty() or kind.is_empty() or text.is_empty() \
			or String(recipe_id).length() > RECIPE_ID_MAX_LENGTH \
			or (kind != &"hint" and kind != &"success") \
			or text.length() > OBSERVATION_MAX_LENGTH or not is_finite(session_time):
		return false
	var key := "%s:%s" % [recipe_id, kind]
	if _recorded_kinds.has(key):
		return false
	_discovered[recipe_id] = true
	_recorded_kinds[key] = true
	_observations.append({
		recipe_id = recipe_id,
		kind = kind,
		text = text,
		session_time = maxf(session_time, 0.0),
	})
	if _observations.size() > MAX_OBSERVATIONS:
		_observations.pop_front()
	if notify:
		observation_added.emit(text)
	return true


func replace_snapshot(discovered_ids: PackedStringArray, observation_recipe_ids: PackedStringArray,
		kinds: PackedStringArray, texts: PackedStringArray, times: PackedFloat32Array) -> bool:
	if observation_recipe_ids.size() != kinds.size() \
			or kinds.size() != texts.size() or texts.size() != times.size() \
			or texts.size() > MAX_OBSERVATIONS:
		return false
	for recipe_id: String in discovered_ids:
		if recipe_id.is_empty() or recipe_id.length() > RECIPE_ID_MAX_LENGTH:
			return false
	for index: int in range(texts.size()):
		if observation_recipe_ids[index].is_empty() \
				or observation_recipe_ids[index].length() > RECIPE_ID_MAX_LENGTH \
				or (kinds[index] != "hint" and kinds[index] != "success") \
				or texts[index].is_empty() or texts[index].length() > OBSERVATION_MAX_LENGTH \
				or not is_finite(times[index]):
			return false
	_discovered.clear()
	_observations.clear()
	_recorded_kinds.clear()
	for recipe_id: String in discovered_ids:
		_discovered[StringName(recipe_id)] = true
	for index: int in range(texts.size()):
		if not apply_observation(StringName(observation_recipe_ids[index]), StringName(kinds[index]),
				texts[index], times[index], false):
			return false
	return true


func snapshot() -> Dictionary:
	var discovered := PackedStringArray()
	for recipe_id: StringName in discovered_recipe_ids():
		discovered.append(String(recipe_id))
	var recipe_ids := PackedStringArray()
	var kinds := PackedStringArray()
	var texts := PackedStringArray()
	var times := PackedFloat32Array()
	for observation: Dictionary in _observations:
		recipe_ids.append(String(observation.recipe_id))
		kinds.append(String(observation.kind))
		texts.append(String(observation.text))
		times.append(float(observation.session_time))
	return {
		discovered = discovered,
		observation_recipe_ids = recipe_ids,
		kinds = kinds,
		texts = texts,
		times = times,
	}

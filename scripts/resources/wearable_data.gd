class_name WearableData
extends ItemData

const VALID_SLOTS: Array[StringName] = [&"outfit", &"back", &"main_hand"]

@export var equip_slot: StringName = &"outfit"
@export var visual_id: StringName = &""
## 생존 계층이 읽는 작은 수치 맵. 첫 항목은 보온(warmth)이다.
@export var modifiers: Dictionary = {warmth = 0.0}
@export var noise_modifier: float = 0.0
@export var smell_modifier: float = 0.0
@export var wetness_modifier: float = 0.0
@export_flags("Wet", "Bloody", "Dirty", "Damaged") var condition_flags: int = 0


func is_valid_wearable() -> bool:
	if not VALID_SLOTS.has(equip_slot):
		push_error("WearableData %s: invalid equip_slot %s" % [id, equip_slot])
		return false
	if visual_id == &"":
		push_error("WearableData %s: missing visual_id; safe visual fallback will be used" % id)
		return false
	if modifiers.is_empty() or not modifiers.has("warmth"):
		push_error("WearableData %s: modifiers must include warmth" % id)
		return false
	for key: Variant in modifiers:
		var value: Variant = modifiers[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			push_error("WearableData %s: invalid modifier %s" % [id, key])
			return false
	for value: float in [noise_modifier, smell_modifier, wetness_modifier]:
		if not is_finite(value):
			push_error("WearableData %s: non-finite environmental modifier" % id)
			return false
	return true

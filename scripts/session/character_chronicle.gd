class_name CharacterChronicle
extends Node

## A host-authoritative, deliberately small record of what happened to this character.
## It listens to existing gameplay signals; it does not own progression or publish events.

const SOLUTIONS: Array[StringName] = [&"spear", &"bow", &"lure", &"escape"]
const TRACKED_EQUIPMENT_SLOTS: Array[StringName] = [&"outfit", &"main_hand"]
const TIMELINE_CAPACITY: int = 8
const POSITION_SAMPLE_SECONDS: float = 0.25
const TELEPORT_DISTANCE_PX: float = 256.0

@export var player_path: NodePath = ^"../Player"
@export var clock_path: NodePath = ^"../SessionClock"
@export var objective_path: NodePath = ^"../LoopObjective"

var survival_days: int = 1
var scar_count: int = 0
var repaired_outfit_count: int = 0
var discovered_principle_count: int = 0
var solution_counts: Dictionary = {
	&"spear": 0,
	&"bow": 0,
	&"lure": 0,
	&"escape": 0,
}
var session_results: Array[Dictionary] = []
var food_safety_state: Dictionary = {}
var distance_traveled_px: float = 0.0
var visited_zones: PackedStringArray = PackedStringArray()
var equipment_usage_seconds: Dictionary = {
	&"outfit": {},
	&"main_hand": {},
}
var timeline: Array[Dictionary] = []

var _player: Player
var _clock: SessionClock
var _objective: LoopObjective
var _knowledge: CraftingKnowledge
var _surviving_bleed: bool = false
var _outfit_was_damaged: bool = false
var _last_attack_solution: StringName = &""
var _position_sample_elapsed: float = 0.0
var _local_elapsed: float = 0.0
var _last_sample_position: Vector2 = Vector2.ZERO
var _has_position_sample: bool = false
var _equipment_started_at: Dictionary = {}
var _equipment_current: Dictionary = {}
var _zone_provider: Node = null


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	_clock = get_node_or_null(clock_path) as SessionClock
	_objective = get_node_or_null(objective_path) as LoopObjective
	if _player == null:
		return
	_knowledge = CraftingKnowledge.ensure_on(_player)
	_outfit_was_damaged = (_player.equipment.condition_flags \
		& EquipmentComponent.DAMAGED_FLAG) != 0
	_player.equipment.equipment_changed.connect(_on_equipment_changed)
	_knowledge.observation_added.connect(_on_knowledge_observation)
	if _clock != null:
		_clock.time_changed.connect(_on_time_changed)
	if _objective != null:
		_objective.outcome_changed.connect(_on_outcome_changed)
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.bleeding_started.connect(_on_bleeding_started)
		event_bus.bleeding_stopped.connect(_on_bleeding_stopped)
		event_bus.noise_emitted.connect(_on_noise_emitted)
		event_bus.item_picked_up.connect(_on_item_picked_up)
	for node: Node in get_tree().get_nodes_in_group(&"raptor"):
		_watch_raptor(node as Raptor)
	get_tree().node_added.connect(_on_node_added)
	_zone_provider = get_node_or_null(^"../World")
	for slot: StringName in TRACKED_EQUIPMENT_SLOTS:
		_equipment_current[slot] = _player.equipment.get_equipped(slot)
		_equipment_started_at[slot] = _clock_total_seconds()
	track_position_sample(_player.global_position, _zone_at(_player.global_position))
	_connect_crafting.call_deferred()
	_refresh_derived_state()


func _physics_process(delta: float) -> void:
	_local_elapsed += maxf(delta, 0.0)
	if not multiplayer.is_server() or _player == null:
		return
	_position_sample_elapsed += delta
	if _position_sample_elapsed < POSITION_SAMPLE_SECONDS:
		return
	_position_sample_elapsed = fmod(_position_sample_elapsed, POSITION_SAMPLE_SECONDS)
	track_position_sample(_player.global_position, _zone_at(_player.global_position))


func snapshot() -> Dictionary:
	_refresh_derived_state()
	_flush_equipment_usage()
	if _player != null:
		food_safety_state = _player.stats.food_safety_snapshot()
	return {
		"survival_days": survival_days,
		"scar_count": scar_count,
		"repaired_outfit_count": repaired_outfit_count,
		"discovered_principle_count": discovered_principle_count,
		"solution_counts": _string_key_counts(),
		"session_results": session_results.duplicate(true),
		"food_safety": food_safety_state.duplicate(),
		"distance_traveled_px": distance_traveled_px,
		"visited_zones": Array(visited_zones),
		"equipment_usage_seconds": equipment_usage_seconds.duplicate(true),
		"timeline": timeline.duplicate(true),
	}


func apply_snapshot(state: Dictionary) -> bool:
	if not validate_snapshot(state):
		return false
	survival_days = int(state.get("survival_days", 1))
	scar_count = int(state.get("scar_count", 0))
	repaired_outfit_count = int(state.get("repaired_outfit_count", 0))
	discovered_principle_count = int(state.get("discovered_principle_count", 0))
	var counts: Dictionary = state.get("solution_counts", {})
	for solution: StringName in SOLUTIONS:
		solution_counts[solution] = int(counts.get(String(solution), counts.get(solution, 0)))
	session_results = []
	for raw: Variant in state.get("session_results", []):
		session_results.append((raw as Dictionary).duplicate(true))
	var food_safety: Variant = state.get("food_safety", {})
	food_safety_state = (food_safety as Dictionary).duplicate()
	distance_traveled_px = float(state.get("distance_traveled_px", 0.0))
	visited_zones = PackedStringArray(state.get("visited_zones", []))
	var usage: Dictionary = state.get("equipment_usage_seconds", {})
	for slot: StringName in TRACKED_EQUIPMENT_SLOTS:
		equipment_usage_seconds[slot] = (usage.get(
			String(slot), usage.get(slot, {})) as Dictionary).duplicate()
	timeline = []
	for raw: Variant in state.get("timeline", []):
		timeline.append((raw as Dictionary).duplicate(true))
	if not food_safety_state.is_empty() and _player != null \
			and not _player.stats.apply_food_safety_snapshot(food_safety_state):
		return false
	apply_scar_visual()
	_has_position_sample = false
	if _player != null:
		track_position_sample(_player.global_position, _zone_at(_player.global_position))
	for slot: StringName in TRACKED_EQUIPMENT_SLOTS:
		_equipment_current[slot] = _player.equipment.get_equipped(slot) if _player != null else &""
		_equipment_started_at[slot] = _clock_total_seconds()
	return true


static func validate_snapshot(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	for key: String in ["survival_days", "scar_count", "repaired_outfit_count",
			"discovered_principle_count"]:
		if int((state as Dictionary).get(key, 0)) < 0:
			return false
	var results: Variant = (state as Dictionary).get("session_results", [])
	if not results is Array:
		return false
	for raw: Variant in results:
		if not raw is Dictionary:
			return false
	var food_safety: Variant = (state as Dictionary).get("food_safety", {})
	if not food_safety is Dictionary:
		return false
	var distance: Variant = (state as Dictionary).get("distance_traveled_px", 0.0)
	if not (distance is int or distance is float) or not is_finite(float(distance)) \
			or float(distance) < 0.0:
		return false
	var zones: Variant = (state as Dictionary).get("visited_zones", [])
	if not zones is Array and not zones is PackedStringArray:
		return false
	for zone: Variant in zones:
		if not zone is String or String(zone) not in ["Z01", "Z02", "Z03"]:
			return false
	var usage: Variant = (state as Dictionary).get("equipment_usage_seconds", {})
	if not usage is Dictionary:
		return false
	for slot: StringName in TRACKED_EQUIPMENT_SLOTS:
		var slot_usage: Variant = (usage as Dictionary).get(String(slot),
			(usage as Dictionary).get(slot, {}))
		if not slot_usage is Dictionary:
			return false
		for seconds: Variant in (slot_usage as Dictionary).values():
			if not (seconds is int or seconds is float) or not is_finite(float(seconds)) \
					or float(seconds) < 0.0:
				return false
	var events: Variant = (state as Dictionary).get("timeline", [])
	if not events is Array or (events as Array).size() > TIMELINE_CAPACITY:
		return false
	for event: Variant in events:
		if not event is Dictionary or not (event as Dictionary).get("text", "") is String:
			return false
		var timestamp: Variant = (event as Dictionary).get("time", 0.0)
		if not (timestamp is int or timestamp is float) or not is_finite(float(timestamp)) \
				or float(timestamp) < 0.0:
			return false
	return true


func record_solution(solution: StringName) -> void:
	if not multiplayer.is_server() or not SOLUTIONS.has(solution):
		return
	solution_counts[solution] = int(solution_counts.get(solution, 0)) + 1
	record_timeline(_solution_sentence(solution), &"solution")


func record_result(outcome: StringName, cause: String = "") -> void:
	if not multiplayer.is_server():
		return
	var entry := {
		"outcome": String(outcome),
		"day": survival_days,
		"cause": cause,
	}
	if not session_results.is_empty() and session_results.back() == entry:
		return
	session_results.append(entry)
	if session_results.size() > 12:
		session_results.pop_front()
	if not cause.is_empty():
		record_timeline(cause, &"death")


func track_position_sample(position: Vector2, zone: String = "") -> void:
	if not position.is_finite():
		return
	if _has_position_sample:
		var step := _last_sample_position.distance_to(position)
		if step <= TELEPORT_DISTANCE_PX:
			distance_traveled_px += step
	_last_sample_position = position
	_has_position_sample = true
	if zone in ["Z01", "Z02", "Z03"] and not visited_zones.has(zone):
		visited_zones.append(zone)
		record_timeline("%s에 처음 발을 들였다." % zone, &"discovery")


func record_timeline(sentence: String, category: StringName = &"event") -> void:
	if sentence.strip_edges().is_empty():
		return
	var text := sentence.strip_edges()
	if not text.ends_with(".") and not text.ends_with("다."):
		text += "."
	var entry := {
		"time": _clock_total_seconds(),
		"text": "%d일 %s, %s" % [_current_day(), _phase_label(), text],
		"category": String(category),
	}
	if not timeline.is_empty() and timeline.back().text == entry.text:
		return
	timeline.append(entry)
	while timeline.size() > TIMELINE_CAPACITY:
		timeline.pop_front()


func representative_solution() -> StringName:
	var best: StringName = &""
	var best_count: int = 0
	for solution: StringName in SOLUTIONS:
		var count := int(solution_counts.get(solution, 0))
		if count > best_count:
			best = solution
			best_count = count
	return best


func reflection_lines() -> PackedStringArray:
	_refresh_derived_state()
	var lines := PackedStringArray()
	lines.append("%d일을 살았다. 흉터 %s." % [survival_days, _korean_count(scar_count)])
	var solution := representative_solution()
	if not solution.is_empty():
		lines.append(_solution_sentence(solution))
	if repaired_outfit_count > 0 or discovered_principle_count > 0:
		lines.append("옷을 %d번 수선했고, 제작 원리 %d가지를 알아냈다." % [
			repaired_outfit_count, discovered_principle_count])
	return lines


func reflection_text(max_lines: int = -1) -> String:
	if max_lines < 0:
		return death_summary_text()
	var lines := reflection_lines()
	var selected := PackedStringArray()
	for index: int in range(mini(max_lines, lines.size())):
		selected.append(lines[index])
	return "\n".join(selected)


func death_summary_text() -> String:
	_refresh_derived_state()
	_flush_equipment_usage()
	var zones := ", ".join(visited_zones) if not visited_zones.is_empty() else "기록 없음"
	var gear := representative_equipment_text()
	var lines := PackedStringArray([
		"생존 %d일 · 이동 %.1f km" % [survival_days, distance_traveled_px / 1000.0],
		"발견 지역  %s" % zones,
		"대표 장비  %s" % gear,
		"주요 사건",
	])
	for entry: Dictionary in _tail_events(timeline, 4):
		lines.append("· %s" % String(entry.text))
	var recent := last_day_timeline()
	lines.append("마지막 하루")
	if recent.is_empty():
		lines.append("· 남겨진 행동 기록이 없다.")
	else:
		for entry: Dictionary in _tail_events(recent, 3):
			lines.append("· %s" % String(entry.text))
	return "\n".join(lines)


func representative_equipment_text() -> String:
	var names := PackedStringArray()
	for slot: StringName in TRACKED_EQUIPMENT_SLOTS:
		var best_id := _representative_item_id(slot)
		if best_id.is_empty():
			continue
		var item: ItemData = get_node("/root/GameData").get_item(best_id)
		names.append(item.display_name if item != null else String(best_id))
	return " · ".join(names) if not names.is_empty() else "맨손"


func last_day_timeline() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cutoff := maxf(_clock_total_seconds() - _day_duration_seconds(), 0.0)
	for entry: Dictionary in timeline:
		if float(entry.get("time", 0.0)) >= cutoff:
			result.append(entry)
	return result


func continue_summary() -> String:
	_refresh_derived_state()
	return "%d일 생존 · 흉터 %s" % [survival_days, _korean_count(scar_count)]


func apply_scar_visual() -> void:
	if _player == null:
		return
	var rig := _player.get_node_or_null("VisualRig") as PlayerVisualRig
	if rig == null or rig.state_overlay == null:
		return
	var overlay := rig.state_overlay
	overlay.visible = scar_count > 0
	if scar_count <= 0:
		return
	if overlay.sprite_frames == null:
		var image := Image.create(7, 3, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for x: int in range(7):
			image.set_pixel(x, 1, Color(0.42, 0.08, 0.06, 0.9))
		image.set_pixel(1, 0, Color(0.62, 0.15, 0.1, 0.85))
		image.set_pixel(5, 2, Color(0.62, 0.15, 0.1, 0.85))
		var frames := SpriteFrames.new()
		frames.add_frame(&"default", ImageTexture.create_from_image(image))
		overlay.sprite_frames = frames
	overlay.position = Vector2(0, -27)
	overlay.scale = Vector2.ONE * (1.0 + minf(float(scar_count - 1) * 0.08, 0.4))
	overlay.modulate = Color(1.0, 1.0, 1.0, minf(0.65 + scar_count * 0.08, 1.0))


func _refresh_derived_state() -> void:
	if _clock != null:
		survival_days = maxi(survival_days, _clock.current_day)
	if _knowledge != null:
		discovered_principle_count = maxi(
			discovered_principle_count, _knowledge.discovered_recipe_ids().size())


func _on_time_changed(day: int, _time: float, _phase: int) -> void:
	if multiplayer.is_server():
		survival_days = maxi(survival_days, day)


func _on_bleeding_started(target: Node) -> void:
	if multiplayer.is_server() and target == _player:
		_surviving_bleed = true
		record_timeline("상처가 벌어져 피를 흘렸다.", &"injury")


func _on_bleeding_stopped(target: Node) -> void:
	if not multiplayer.is_server() or target != _player or not _surviving_bleed:
		return
	_surviving_bleed = false
	if _player.health.is_alive():
		scar_count += 1
		apply_scar_visual()
		record_timeline("상처를 묶어 출혈을 멎게 했다.", &"injury")


func _on_equipment_changed(slot: StringName, item_id: StringName) -> void:
	if slot in TRACKED_EQUIPMENT_SLOTS:
		_flush_equipment_slot(slot)
		_equipment_current[slot] = item_id
		_equipment_started_at[slot] = _clock_total_seconds()
		if multiplayer.is_server() and not item_id.is_empty():
			var item: ItemData = get_node("/root/GameData").get_item(item_id)
			record_timeline("%s을 갖춰 입었다." % (
				item.display_name if item != null else String(item_id)), &"equipment")
	if slot != &"outfit":
		return
	var damaged := (_player.equipment.condition_flags & EquipmentComponent.DAMAGED_FLAG) != 0
	if multiplayer.is_server() and _outfit_was_damaged and not damaged:
		repaired_outfit_count += 1
		record_timeline("해진 옷을 다시 꿰맸다.", &"craft")
	_outfit_was_damaged = damaged


func _on_knowledge_observation(text: String) -> void:
	if multiplayer.is_server():
		discovered_principle_count = _knowledge.discovered_recipe_ids().size()
		record_timeline(text, &"discovery")


func _on_noise_emitted(_position: Vector2, _radius: float, source: Node) -> void:
	if not multiplayer.is_server() or source != _player:
		return
	var weapon := _player.equipment.get_equipped(&"main_hand")
	if weapon == &"stone_spear":
		_last_attack_solution = &"spear"
	elif weapon == &"bow":
		_last_attack_solution = &"bow"


func _on_node_added(node: Node) -> void:
	if node is Raptor:
		_watch_raptor(node as Raptor)
	elif node is RemoteNoiseLure or node is ThrowableBait:
		# Placement itself is the existing system event. Counting it here avoids
		# confusing the lure's 260 px sound with an equally loud bush/melee noise.
		record_solution(&"lure")


func _watch_raptor(raptor: Raptor) -> void:
	if raptor == null:
		return
	if not raptor.died.is_connected(_on_raptor_died):
		raptor.died.connect(_on_raptor_died)
	if not raptor.state_changed.is_connected(_on_raptor_state_changed):
		raptor.state_changed.connect(_on_raptor_state_changed)


func _on_raptor_died(_carcass: Carcass) -> void:
	record_timeline("랩터 한 마리를 쓰러뜨렸다.", &"hunt")
	if not _last_attack_solution.is_empty():
		record_solution(_last_attack_solution)
	_last_attack_solution = &""


func _on_raptor_state_changed(previous: int, current: int) -> void:
	if previous == Raptor.State.CHASE and current != Raptor.State.CHASE \
			and _player != null and _player.health.is_alive():
		record_solution(&"escape")


func _on_outcome_changed(outcome: LoopObjective.Outcome) -> void:
	if outcome == LoopObjective.Outcome.PENDING:
		return
	var names: Array[StringName] = [&"pending", &"stable_escape", &"forced_escape", &"remain", &"failed"]
	record_result(names[int(outcome)], _objective.compose_result_cause() \
		if outcome == LoopObjective.Outcome.FAILED else "")


func _on_item_picked_up(item_id: StringName, by: Node) -> void:
	if not multiplayer.is_server() or by != _player:
		return
	if item_id == &"cooked_meat":
		record_timeline("불에 익힌 고기를 챙겼다.", &"food")


func _connect_crafting() -> void:
	var net_crafting := get_node_or_null(^"../NetCrafting")
	if net_crafting == null:
		return
	for child: Node in net_crafting.get_children():
		if child is Crafting and not (child as Crafting).crafted.is_connected(_on_crafted):
			(child as Crafting).crafted.connect(_on_crafted)
			return


func _on_crafted(recipe_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var recipe: RecipeData = get_node("/root/GameData").get_recipe(recipe_id)
	if recipe == null:
		return
	if recipe.result != null:
		record_timeline("%s을 만들었다." % recipe.result.display_name, &"craft")


func _flush_equipment_usage() -> void:
	for slot: StringName in TRACKED_EQUIPMENT_SLOTS:
		_flush_equipment_slot(slot)


func _flush_equipment_slot(slot: StringName) -> void:
	var item_id := StringName(_equipment_current.get(slot, &""))
	var now := _clock_total_seconds()
	var started := float(_equipment_started_at.get(slot, now))
	if not item_id.is_empty() and now >= started:
		var slot_usage: Dictionary = equipment_usage_seconds.get(slot, {})
		slot_usage[item_id] = float(slot_usage.get(item_id, 0.0)) + now - started
		equipment_usage_seconds[slot] = slot_usage
	_equipment_started_at[slot] = now


func _representative_item_id(slot: StringName) -> StringName:
	var best_id: StringName = &""
	var best_seconds: float = -1.0
	var slot_usage: Dictionary = equipment_usage_seconds.get(slot, {})
	for raw_id: Variant in slot_usage:
		var seconds := float(slot_usage[raw_id])
		if seconds > best_seconds:
			best_seconds = seconds
			best_id = StringName(raw_id)
	return best_id


func _zone_at(position: Vector2) -> String:
	if _zone_provider != null and _zone_provider.has_method("zone_at_world"):
		return String(_zone_provider.call("zone_at_world", position))
	return ""


func _clock_total_seconds() -> float:
	if _clock == null:
		return _local_elapsed
	return float(_clock.current_day - 1) * _clock.day_duration_seconds() \
		+ _clock.time_of_day_seconds


func _day_duration_seconds() -> float:
	return _clock.day_duration_seconds() if _clock != null else 600.0


func _current_day() -> int:
	return _clock.current_day if _clock != null else survival_days


func _phase_label() -> String:
	return _clock.phase_label() if _clock != null else "낮"


static func _tail_events(events: Array[Dictionary], count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(events.size() - count, 0)
	for index: int in range(start, events.size()):
		result.append(events[index])
	return result


func _string_key_counts() -> Dictionary:
	var result: Dictionary = {}
	for solution: StringName in SOLUTIONS:
		result[String(solution)] = int(solution_counts.get(solution, 0))
	return result


func _solution_sentence(solution: StringName) -> String:
	match solution:
		&"spear":
			return "미끼보다 창을 믿었다."
		&"bow":
			return "창보다 활을 믿었다."
		&"lure":
			return "창보다 미끼를 믿었다."
		_:
			return "싸우기보다 살아서 도망치는 법을 믿었다."


static func _korean_count(value: int) -> String:
	const WORDS: Array[String] = ["없음", "하나", "둘", "셋", "넷", "다섯"]
	return WORDS[value] if value >= 0 and value < WORDS.size() else "%d개" % value

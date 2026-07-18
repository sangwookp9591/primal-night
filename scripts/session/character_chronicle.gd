class_name CharacterChronicle
extends Node

## A host-authoritative, deliberately small record of what happened to this character.
## It listens to existing gameplay signals; it does not own progression or publish events.

const SOLUTIONS: Array[StringName] = [&"spear", &"bow", &"lure", &"escape"]

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

var _player: Player
var _clock: SessionClock
var _objective: LoopObjective
var _knowledge: CraftingKnowledge
var _surviving_bleed: bool = false
var _outfit_was_damaged: bool = false
var _last_attack_solution: StringName = &""


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
	for node: Node in get_tree().get_nodes_in_group(&"raptor"):
		_watch_raptor(node as Raptor)
	get_tree().node_added.connect(_on_node_added)
	_refresh_derived_state()


func snapshot() -> Dictionary:
	_refresh_derived_state()
	return {
		"survival_days": survival_days,
		"scar_count": scar_count,
		"repaired_outfit_count": repaired_outfit_count,
		"discovered_principle_count": discovered_principle_count,
		"solution_counts": _string_key_counts(),
		"session_results": session_results.duplicate(true),
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
	apply_scar_visual()
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
	return true


func record_solution(solution: StringName) -> void:
	if not multiplayer.is_server() or not SOLUTIONS.has(solution):
		return
	solution_counts[solution] = int(solution_counts.get(solution, 0)) + 1


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


func reflection_text(max_lines: int = 3) -> String:
	var lines := reflection_lines()
	var selected := PackedStringArray()
	for index: int in range(mini(max_lines, lines.size())):
		selected.append(lines[index])
	return "\n".join(selected)


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


func _on_bleeding_stopped(target: Node) -> void:
	if not multiplayer.is_server() or target != _player or not _surviving_bleed:
		return
	_surviving_bleed = false
	if _player.health.is_alive():
		scar_count += 1
		apply_scar_visual()


func _on_equipment_changed(slot: StringName, _item_id: StringName) -> void:
	if slot != &"outfit":
		return
	var damaged := (_player.equipment.condition_flags & EquipmentComponent.DAMAGED_FLAG) != 0
	if multiplayer.is_server() and _outfit_was_damaged and not damaged:
		repaired_outfit_count += 1
	_outfit_was_damaged = damaged


func _on_knowledge_observation(_text: String) -> void:
	if multiplayer.is_server():
		discovered_principle_count = _knowledge.discovered_recipe_ids().size()


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

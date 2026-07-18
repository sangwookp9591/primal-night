class_name SaveService
extends Node

signal save_completed(reason: StringName)
signal save_failed(message: String)

const FORMAT_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://saves/slot_1.save"
const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/items/world_item.tscn")

static var pending_snapshot: Dictionary = {}
static var pending_death_recovery: bool = false
static var launch_requested: bool = false

@export var save_path: String = DEFAULT_SAVE_PATH
@export var enabled: bool = true

var last_error: String = ""
var _root: Node

func _ready() -> void:
	_root = get_parent()
	# Tests and harnesses instantiate main.tscn directly. Only an explicit title launch enables I/O.
	enabled = enabled and launch_requested
	launch_requested = false
	var clock := _root.get_node_or_null("SessionClock") as SessionClock
	if clock != null:
		clock.phase_changed.connect(_on_phase_changed)
	for node: Node in get_tree().get_nodes_in_group(&"bedding"):
		if _root.is_ancestor_of(node) and node.has_signal("rested"):
			node.rested.connect(_on_bedding_rested)
	if not pending_snapshot.is_empty():
		var snapshot := pending_snapshot
		var death_recovery := pending_death_recovery
		pending_snapshot = {}
		pending_death_recovery = false
		apply_snapshot.call_deferred(snapshot, death_recovery)

func save_now(reason: StringName = &"manual") -> bool:
	if not enabled or not multiplayer.is_server():
		return false
	var snapshot := collect_snapshot()
	var directory := save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
		if mkdir_error != OK:
			return _fail("저장 폴더를 만들 수 없습니다.")
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _fail("저장 파일을 열 수 없습니다.")
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	save_completed.emit(reason)
	return true

## Death is metadata on the checkpoint, not a new checkpoint: the dead body/world state
## must never replace the last recoverable snapshot.
func record_death(cause: String) -> bool:
	if not enabled or not multiplayer.is_server() or not FileAccess.file_exists(save_path):
		return false
	var loaded := load_file(save_path)
	if not loaded.ok:
		return false
	var snapshot: Dictionary = loaded.snapshot
	var clock := _root.get_node_or_null("SessionClock") as SessionClock
	snapshot.death_record = {
		"cause": cause,
		"day": clock.current_day if clock != null else 1,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _fail("사망 기록을 저장하지 못했습니다.")
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	return true

func collect_snapshot() -> Dictionary:
	var player := _root.get_node("Player") as Player
	var clock := _root.get_node("SessionClock") as SessionClock
	var objective := _root.get_node("LoopObjective") as LoopObjective
	var difficulty := _root.get_node("DifficultyRuntime") as DifficultyRuntime
	return {
		"version": FORMAT_VERSION,
		"difficulty": String(difficulty.config.id),
		"player": _player_snapshot(player),
		"clock": {
			"day": clock.current_day,
			"time": clock.time_of_day_seconds,
			"running": clock.running,
		},
		"objective": {
			"outcome": int(objective.outcome),
			"risk_exposed": objective.risk_exposed,
			"bleeding_treated": objective.bleeding_treated,
			"fire_maintained": objective.fire_maintained,
			"death_cause": objective.death_cause_text,
			"cause_history": _cause_history_snapshot(objective.cause_history),
		},
		"world_items": _world_item_snapshots(),
		"campfires": _campfire_snapshots(),
		"base_camp": _base_camp_snapshot(),
		"carcasses": _carcass_snapshots(),
		"creatures": _creature_snapshots(),
		"death_record": {
			"cause": objective.death_cause_text,
			"day": clock.current_day,
		},
	}

func apply_snapshot(snapshot: Dictionary, death_recovery: bool = false) -> bool:
	var validation := validate_snapshot(snapshot)
	if not validation.ok:
		return _fail(validation.message)
	var difficulty := _root.get_node("DifficultyRuntime") as DifficultyRuntime
	difficulty.apply_preset(StringName(snapshot.difficulty))
	var player := _root.get_node("Player") as Player
	if not _apply_player(player, snapshot.player):
		return _fail("플레이어 저장 상태가 올바르지 않습니다.")
	var clock := _root.get_node("SessionClock") as SessionClock
	clock.apply_replicated(int(snapshot.clock.day), float(snapshot.clock.time),
		bool(snapshot.clock.running))
	var objective := _root.get_node("LoopObjective") as LoopObjective
	var state: Dictionary = snapshot.objective
	objective.outcome = int(state.outcome) as LoopObjective.Outcome
	objective.risk_exposed = bool(state.risk_exposed)
	objective.bleeding_treated = bool(state.bleeding_treated)
	objective.fire_maintained = bool(state.fire_maintained)
	objective.death_cause_text = String(state.get("death_cause", ""))
	objective.cause_history = _restore_cause_history(state.get("cause_history", []))
	_apply_world_items(snapshot.world_items)
	_apply_campfires(snapshot.campfires)
	_apply_base_camp(snapshot.base_camp)
	_apply_carcasses(snapshot.carcasses)
	_apply_creatures(snapshot.creatures)
	if death_recovery:
		player.inventory.apply_death_keep_ratio(difficulty.config.death_item_keep_ratio, _root)
	return true

static func has_save(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

static func load_file(path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "이어갈 저장이 없습니다."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "저장 파일을 읽을 수 없습니다."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "message": "저장 파일이 손상되어 이어갈 수 없습니다."}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"ok": false, "message": "저장 파일이 손상되어 이어갈 수 없습니다."}
	var checked := validate_snapshot(parsed)
	if not checked.ok:
		return checked
	return {"ok": true, "snapshot": parsed}

static func validate_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "message": "저장 파일이 손상되어 이어갈 수 없습니다."}
	var snapshot := value as Dictionary
	if int(snapshot.get("version", -1)) != FORMAT_VERSION:
		return {"ok": false, "message": "지원하지 않는 저장 버전입니다. 새 게임을 시작해 주세요."}
	for key: String in ["difficulty", "player", "clock", "objective", "world_items",
			"campfires", "base_camp", "carcasses", "creatures"]:
		if not snapshot.has(key):
			return {"ok": false, "message": "저장 파일에 필수 상태가 없어 이어갈 수 없습니다."}
	if not snapshot.player is Dictionary or not snapshot.clock is Dictionary \
			or not snapshot.objective is Dictionary:
		return {"ok": false, "message": "저장 파일의 상태 형식이 올바르지 않습니다."}
	return {"ok": true, "message": ""}

static func prepare_continue(path: String = DEFAULT_SAVE_PATH,
		death_recovery: bool = false) -> Dictionary:
	var loaded := load_file(path)
	if not loaded.ok:
		return loaded
	pending_snapshot = loaded.snapshot
	pending_death_recovery = death_recovery
	launch_requested = true
	DifficultyRuntime.select_for_next_game(StringName(pending_snapshot.difficulty))
	return {"ok": true, "message": ""}

func _player_snapshot(player: Player) -> Dictionary:
	return {
		"position": _vec(player.global_position),
		"stats": {
			"temperature": player.stats.temperature, "water": player.stats.water,
			"food": player.stats.food, "fatigue": player.stats.fatigue,
		},
		"health": {
			"current": player.health.current_health,
			"bleeding": player.health.is_bleeding,
		},
		"inventory": player.inventory.get_transaction_snapshot(),
		# Reuse the exact NetEquipment representation.
		"equipment": player.equipment.get_snapshot(),
	}

func _apply_player(player: Player, state: Dictionary) -> bool:
	if not state.has("stats") or not state.has("health") or not state.has("inventory") \
			or not state.has("equipment"):
		return false
	player.global_position = _unvec(state.get("position", [0.0, 0.0]))
	var stats: Dictionary = state.stats
	player.stats.apply_replicated(float(stats.temperature), float(stats.water),
		float(stats.food), float(stats.fatigue))
	var health: Dictionary = state.health
	player.health.apply_replicated(float(health.current), bool(health.bleeding))
	var slots: Array[Dictionary] = []
	for raw: Variant in state.inventory:
		if not raw is Dictionary:
			return false
		slots.append((raw as Dictionary).duplicate())
	if not player.inventory.restore_transaction_snapshot(slots):
		return false
	return player.equipment.apply_snapshot(state.equipment)

func _world_item_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(&"world_item"):
		var item := node as WorldItem
		if item != null and _root.is_ancestor_of(item) and item.count > 0:
			result.append({"path": String(_root.get_path_to(item)), "id": String(item.item_id),
				"count": item.count, "position": _vec(item.global_position)})
	return result

func _apply_world_items(states: Array) -> void:
	var remaining: Dictionary = {}
	for raw: Variant in states:
		if raw is Dictionary:
			remaining[String(raw.path)] = raw
	for node: Node in get_tree().get_nodes_in_group(&"world_item"):
		var item := node as WorldItem
		if item == null or not _root.is_ancestor_of(item):
			continue
		var path := String(_root.get_path_to(item))
		if remaining.has(path):
			var state: Dictionary = remaining[path]
			item.item_id = StringName(state.id)
			item.count = int(state.count)
			item.global_position = _unvec(state.position)
			remaining.erase(path)
		else:
			item.queue_free()
	for state: Dictionary in remaining.values():
		var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
		item.item_id = StringName(state.id)
		item.count = int(state.count)
		_root.add_child(item)
		item.global_position = _unvec(state.position)

func _campfire_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(&"campfire"):
		var fire := node as Campfire
		if fire != null and _root.is_ancestor_of(fire):
			result.append({"path": String(_root.get_path_to(fire)), "lit": fire.is_lit,
				"fuel": fire.fuel_remaining, "position": _vec(fire.global_position)})
	return result

func _apply_campfires(states: Array) -> void:
	for raw: Variant in states:
		if not raw is Dictionary:
			continue
		var fire := _root.get_node_or_null(NodePath(raw.path)) as Campfire
		if fire == null:
			continue
		fire.global_position = _unvec(raw.position)
		fire.extinguish()
		if bool(raw.lit):
			fire.light()
			fire.fuel_remaining = maxf(float(raw.fuel), 0.0)

func _base_camp_snapshot() -> Dictionary:
	var cache := _root.get_node_or_null("StorageCache") as StorageCache
	var rack := _root.get_node_or_null("DryingRack") as DryingRack
	return {
		# Same Inventory slot dictionaries used by NetBaseCamp transactions.
		"storage_cache": cache.inventory.get_transaction_snapshot() if cache != null else [],
		"drying_rack": {"item_id": String(rack.item_id),
			"elapsed": rack.elapsed_seconds} if rack != null else {},
		"bedding": {"present": _root.get_node_or_null("Bedding") != null},
	}

func _apply_base_camp(state: Dictionary) -> void:
	var cache := _root.get_node_or_null("StorageCache") as StorageCache
	if cache != null:
		var slots: Array[Dictionary] = []
		for raw: Variant in state.get("storage_cache", []):
			if raw is Dictionary:
				slots.append((raw as Dictionary).duplicate())
		cache.inventory.restore_transaction_snapshot(slots)
	var rack := _root.get_node_or_null("DryingRack") as DryingRack
	var rack_state: Dictionary = state.get("drying_rack", {})
	if rack != null and not rack_state.is_empty():
		rack.apply_state(StringName(rack_state.item_id), float(rack_state.elapsed))

func _carcass_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(&"carcass"):
		var carcass := node as Carcass
		if carcass != null and _root.is_ancestor_of(carcass):
			result.append({"path": String(_root.get_path_to(carcass)),
				"position": _vec(carcass.global_position), "yield_mask": carcass.yield_mask,
				"stage_elapsed": carcass._stage_elapsed})
	return result

func _apply_carcasses(states: Array) -> void:
	for raw: Variant in states:
		if raw is Dictionary:
			var carcass := _root.get_node_or_null(NodePath(raw.path)) as Carcass
			if carcass != null:
				carcass.global_position = _unvec(raw.position)
				carcass.yield_mask = int(raw.yield_mask)
				carcass._stage_elapsed = float(raw.stage_elapsed)

func _creature_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: StringName in [&"raptor", &"scavenger"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var creature := node as Node2D
			if creature != null and _root.is_ancestor_of(creature):
				result.append({"path": String(_root.get_path_to(creature)),
					"kind": String(group), "position": _vec(creature.global_position),
					"state": int(creature.get("state")), "alive": true})
	return result

func _apply_creatures(states: Array) -> void:
	var alive_paths: Dictionary = {}
	for raw: Variant in states:
		if not raw is Dictionary:
			continue
		alive_paths[String(raw.path)] = true
		var creature := _root.get_node_or_null(NodePath(raw.path)) as Node2D
		if creature != null:
			creature.global_position = _unvec(raw.position)
			creature.set("state", int(raw.state))
	for group: StringName in [&"raptor", &"scavenger"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if _root.is_ancestor_of(node) \
					and not alive_paths.has(String(_root.get_path_to(node))):
				node.queue_free()

func _cause_history_snapshot(history: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in history:
		result.append({"kind": String(entry.kind), "position": _vec(entry.position),
			"time": float(entry.time)})
	return result

func _restore_cause_history(states: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in states:
		if raw is Dictionary:
			result.append({"kind": StringName(raw.kind), "position": _unvec(raw.position),
				"time": float(raw.time)})
	return result

func _on_phase_changed(phase: SessionClock.Phase) -> void:
	if phase == SessionClock.Phase.NIGHT or phase == SessionClock.Phase.DAYLIGHT:
		save_now(&"day_night_boundary")

func _on_bedding_rested(_who: Player) -> void:
	save_now(&"bedding")

func _fail(message: String) -> bool:
	last_error = message
	save_failed.emit(message)
	return false

static func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]

static func _unvec(value: Variant) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

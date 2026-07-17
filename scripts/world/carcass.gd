class_name Carcass
extends Area2D

## 시드 배치된 사체. 도구를 들고 홀드해 구간 단위로 해체한다 (정본 §14.4).
##
## 사체는 개체를 죽여서 생기지 않는다 — 정본 §14.5 의 SpawnTable 월드 오브젝트다.
## 그래서 여기에 사망·전투 경로는 없다.
##
## interactable 계약 (덕 타이핑, Interactor 참조):
##   can_interact / get_hold_seconds / get_prompt / interact / on_hold_started / on_hold_ended
##
## 홀드 1회 = 구간 1개(25%). 구간을 완료해야 산출이 확정되고, 중단하면 진행만 남는다.
## 진행률을 사체가 소유하는 이유는 정본 §14.4 의 "진행은 사체에 저장" 이다 —
## 플레이어가 바뀌어도 사체를 이어서 해체할 수 있어야 협동 역할 분담이 성립한다.
##
## 권위: 로컬 경로(넷 스택 없는 씬)는 여기서 즉시 확정하고, 넷 스택이 있으면
## `NetButcher` 가 호스트 시계로 홀드 시간을 재검증한 뒤 확정한다 (W5-T2).

const BUTCHER_NOISE: NoiseProfile = preload("res://data/senses/noise_butcher.tres")

## 해체 유지 거리 (정본 §14.4: "거리 72px 초과 시 중단").
const BUTCHER_MAX_DISTANCE_PX: float = 72.0

signal stage_committed(stage: int, granted: Dictionary)

@export var profile: CarcassProfile
@export_range(0, 7, 1) var visual_direction: int = 4

## 확정된 산출 구간 비트마스크. 정본 §14.4 의 `yield_mask` 다.
## 호스트 권위 상태이며 재접속 스냅샷 대상이다 (W5-T2).
var yield_mask: int = 0

var _stage_elapsed: float = 0.0
var _holder: Player = null
## Interactor.begin() 이 can_interact(who) 를 호출한 직후 get_hold_seconds() 를
## 인자 없이 호출한다. 그 사이에 끼어드는 코드가 없어 마지막 질의자가 곧 홀드 주체다.
var _last_asked_by: Player = null
var _event_bus: Node = null
var _noise_emitter: NoiseEmitter = NoiseEmitter.new()
var _grid: SmellGrid = null
var _net_butcher: Node = null
var _net_butcher_cached: bool = false
var _sprite_visual: Node = null


func _ready() -> void:
	set_process(false)
	_sprite_visual = get_node_or_null(^"SpriteVisual")
	# 재접속 월드 스냅샷이 이 그룹만 훑는다 (NetButcher.send_world_snapshot_to) —
	# 매번 씬 트리를 재귀 탐색하지 않는다 (성능문서 6.1).
	add_to_group(&"carcass")
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	if profile == null or not profile.is_valid():
		push_error("Carcass: invalid CarcassProfile on %s" % name)
		return
	# ★ 등록을 한 프레임 미룬다. SmellGrid 는 자기 _ready 에서 smell_grid 그룹에
	# 가입하는데, main.tscn 은 SurvivalDemo(사체)를 SmellGrid 앞에 둔다. 여기서 바로
	# 찾으면 그룹이 비어 있어 신선한 사체가 실기에서 무취가 된다.
	# 씬의 노드 순서에 기대지 않으려면 모든 _ready 가 끝난 뒤에 찾아야 한다.
	_refresh_visual_stage()
	_refresh_smell_source.call_deferred()


func _exit_tree() -> void:
	_unregister_smell()


# --- interactable 계약 -------------------------------------------------------

func can_interact(who: Node) -> bool:
	var player: Player = who as Player
	if player == null or profile == null or is_fully_butchered():
		return false
	_last_asked_by = player
	return best_tool_of(player) != &""


## Interactor 계약용 어댑터. 인자가 없는 시그니처라 "누구의 도구인가"를 받을 수 없어서
## 마지막 질의자를 기준으로 답한다 — Interactor.begin() 이 can_interact(who) 직후
## 이걸 부르는 순서에 기대는 코드다. 새 호출부는 `hold_seconds_for(who)` 를 쓴다.
func get_hold_seconds() -> float:
	return hold_seconds_for(_holder if _holder != null else _last_asked_by)


## 이 플레이어가 지금 잡으면 남은 홀드 시간. 진행이 남아 있으면 그만큼 짧다
## (정본 §14.4 "진행은 사체에 저장"). 도구가 없으면 INF.
func hold_seconds_for(who: Player) -> float:
	return maxf(stage_seconds_for(who) - _stage_elapsed, 0.0)


func get_prompt() -> String:
	if profile == null:
		return ""
	# 표시 문구는 데이터에서 만든다 (설계서 5.6: UI 하드코딩 금지).
	return "%s 해체 (%d/%d)" % [profile.display_name, stages_done(), profile.stage_count]


func on_hold_started(who: Node) -> void:
	_holder = who as Player
	set_process(true)
	var net: Node = _find_net_butcher()
	if net != null:
		# 호스트가 홀드 시작 시각을 기록한다 — 즉시 커밋 변조 차단 (W5-T2).
		net.notify_butcher_hold_started(_holder, self)


func on_hold_ended(who: Node) -> void:
	set_process(false)
	_holder = null
	var net: Node = _find_net_butcher()
	if net != null:
		# 커밋이 먼저 처리됐으면 호스트에서 no-op 이다.
		net.notify_butcher_hold_ended(who as Player, self)


func interact(who: Node) -> void:
	var player: Player = who as Player
	if player == null or not can_interact(player):
		return
	var net: Node = _find_net_butcher()
	if net != null:
		# 검증·확정·복제는 호스트 권위 경로로 간다 (설계서 7.2).
		net.request_stage_commit_for(player, self)
		return
	apply_stage(player)


# --- 구간 확정 ---------------------------------------------------------------

## 로컬 적용 (넷 스택 없는 씬 + 호스트 권위 판정의 실행부).
## 산출을 전부 넣을 수 없으면 **비트를 소모하지 않고** 실패한다 — 정본 §14.4 의
## "재접속·동시 해체에서 같은 bit 두 번 지급 금지"와 짝이 되는 규칙으로,
## 만석 때 산출이 조용히 증발하지 않게 한다 (Crafting.craft 와 같은 선-시뮬레이션 방식).
func apply_stage(who: Player) -> bool:
	if who == null or not is_instance_valid(who) or is_fully_butchered():
		return false
	var stage: int = next_stage()
	if not _grant_yields(who, stage):
		return false

	yield_mask |= 1 << stage
	_stage_elapsed = 0.0
	_emit_butcher_noise(who)
	_refresh_visual_stage()
	_refresh_smell_source()
	stage_committed.emit(stage, profile.yields_for_stage(stage))
	return true


## 산출을 전부 넣을 수 있을 때만 넣는다. 부분 지급은 하지 않는다 —
## 한 구간이 반만 들어가면 나머지를 다시 받을 방법이 없다(bit 는 구간 단위다).
func _grant_yields(who: Player, stage: int) -> bool:
	var granted: Dictionary = profile.yields_for_stage(stage)
	if granted.is_empty():
		return true
	if not _can_fit_all(who, granted):
		return false
	for item_id: StringName in granted:
		who.inventory.add_item(item_id, int(granted[item_id]))
	return true


## 지급 전 여유 확인. 실제로 넣어 보고 되돌리면 무게·스택 경계에서 오차가 생기므로
## 무게와 슬롯을 함께 시뮬레이션한다.
func _can_fit_all(who: Player, granted: Dictionary) -> bool:
	var game_data: Node = get_node_or_null("/root/GameData")
	if game_data == null:
		return false
	var free_slots: int = who.inventory.slot_count - who.inventory.used_slots()
	var weight_room: float = who.inventory.max_weight - who.inventory.total_weight()

	for item_id: StringName in granted:
		var item: ItemData = game_data.get_item(item_id)
		if item == null:
			return false
		var count: int = int(granted[item_id])
		weight_room -= item.weight * float(count)
		if weight_room < 0.0:
			return false
		# 기존 스택의 남은 자리를 먼저 쓰고, 모자란 만큼만 새 슬롯을 센다.
		var limit: int = item.get_stack_limit()
		var room_in_open_stacks: int = 0
		for index: int in range(who.inventory.slot_count):
			var slot: Dictionary = who.inventory.get_slot(index)
			if slot.is_empty() or slot["id"] != item_id:
				continue
			room_in_open_stacks += limit - int(slot["count"])
		var overflow: int = maxi(count - room_in_open_stacks, 0)
		free_slots -= ceili(float(overflow) / float(limit))
		if free_slots < 0:
			return false
	return true


# --- 복제 적용 (호스트 확정의 결과만 받는다) ---------------------------------

## 호스트가 확정한 구간을 복제본에 반영한다. 여기서는 검증하지 않는다 —
## 검증은 이미 호스트에서 끝났고, 복제본이 다시 판정하면 두 결론이 갈린다.
func apply_replicated_stage(stage: int, mask: int, who: Player) -> void:
	if profile == null:
		return
	yield_mask = mask
	_stage_elapsed = 0.0
	_refresh_visual_stage()
	if who != null and is_instance_valid(who):
		var granted: Dictionary = profile.yields_for_stage(stage)
		for item_id: StringName in granted:
			who.inventory.add_item(item_id, int(granted[item_id]))
	_emit_butcher_noise(who)
	_refresh_smell_source()


## 재접속 월드 스냅샷: 확정 상태만 맞춘다. 산출은 지급하지 않는다 —
## 인벤토리 복원은 NetResync 가 소유하므로 여기서 또 주면 아이템이 복제된다.
func apply_replicated_mask(mask: int) -> void:
	yield_mask = mask
	_stage_elapsed = 0.0
	_refresh_visual_stage()
	_refresh_smell_source()


# --- 상태 조회 ---------------------------------------------------------------

func stages_done() -> int:
	var done: int = 0
	for stage: int in range(profile.stage_count):
		if yield_mask & (1 << stage):
			done += 1
	return done


func visual_stage() -> int:
	var done: int = stages_done()
	var total: int = profile.stage_count if profile != null else 4
	if done <= 0:
		return 0
	if done >= total:
		return 3
	if done == 1:
		return 1
	return 2


func _refresh_visual_stage() -> void:
	if _sprite_visual != null and _sprite_visual.has_method("apply_visual"):
		_sprite_visual.apply_visual(visual_direction, visual_stage())


func next_stage() -> int:
	return stages_done()


func is_fully_butchered() -> bool:
	return profile != null and stages_done() >= profile.stage_count


func is_fresh() -> bool:
	return stages_done() == 0


## 이 플레이어가 가진 가장 빠른 해체 도구. 없으면 빈 StringName.
func best_tool_of(who: Player) -> StringName:
	if who == null or not is_instance_valid(who) or profile == null:
		return &""
	var best: StringName = &""
	var best_multiplier: float = INF
	for tool_id: StringName in profile.tool_time_multipliers:
		if not who.inventory.has_item(tool_id, 1):
			continue
		var multiplier: float = profile.time_multiplier_for(tool_id)
		if multiplier < best_multiplier:
			best_multiplier = multiplier
			best = tool_id
	return best


## 이 플레이어의 구간 1개 해체 시간. 도구가 없으면 INF.
func stage_seconds_for(who: Player) -> float:
	var tool_id: StringName = best_tool_of(who)
	if tool_id == &"":
		return INF
	return profile.base_butcher_seconds * profile.time_multiplier_for(tool_id)


func stage_elapsed() -> float:
	return _stage_elapsed


func _process(delta: float) -> void:
	if _holder == null or not is_instance_valid(_holder):
		return
	_stage_elapsed += delta
	# 정본 §14.4: 거리 72px 초과 시 중단. 홀드 중에는 Interactor 가 이동을 잠그므로
	# 걸어서 벗어날 수는 없지만, 텔레포트·넉백·복제 보정이 남아 있어 지킨다.
	if _holder.global_position.distance_to(global_position) > BUTCHER_MAX_DISTANCE_PX:
		_holder.interactor.cancel()


# --- 감각 비용 (W5-T3) -------------------------------------------------------

func _emit_butcher_noise(who: Node) -> void:
	if _event_bus == null:
		return
	# 정본 §14.4: 구간 완료마다 240px, 0.5초 안 반복은 병합.
	# 소음 권위는 사체가 아니라 해체한 주체에 있다 — 클라이언트가 조용한 완료를
	# 주장할 수 없다 (정본 §14.4 / §15.5).
	_noise_emitter.emit_profile(_event_bus, BUTCHER_NOISE, global_position, who)


## 단계별 피 냄새 (정본 §14.4: 신선 80 / 일부 해체 55 / 골격 0).
## 골격 0 은 강도 0 이 아니라 원천 해제다 — SmellGrid 는 강도 0 원천을 등록조차
## 받지 않고, 남겨 두면 매 틱 훑는 목록만 길어진다 (성능문서 5.2).
##
## `SmellSource` 노드 대신 격자에 직접 등록하는 이유: 노드는 강도를 _ready 에 한 번
## 정하고 이후 바꿀 수 없는데, 사체는 구간마다 강도가 내려간다. 소유자 키로 다시
## 등록하면 덮어써지는 이 방식은 Inventory 의 보유 냄새와 같은 패턴이다.
func _refresh_smell_source() -> void:
	var strength: float = current_smell_strength()
	if strength <= 0.0:
		_unregister_smell()
		return
	if _grid == null:
		_grid = SmellGrid.find_in(get_tree())
	if _grid == null:
		return
	_grid.register_smell_source(self, Callable(self, "get_smell_position"),
		strength, profile.smell_interval_seconds, profile.smell_kind)


func current_smell_strength() -> float:
	if profile == null or is_fully_butchered():
		return 0.0
	return profile.fresh_smell_strength if is_fresh() else profile.partial_smell_strength


func get_smell_position() -> Vector2:
	return global_position


func _unregister_smell() -> void:
	if _grid == null:
		return
	_grid.unregister_smell_source(self)
	_grid = null


## 같은 기계(멀티플레이 브랜치)의 NetButcher 만 잡는다 — 헤드리스 하네스에선
## 한 트리에 기계가 2개다. 상호작용 시점 1회 조회 후 캐시 (성능문서 6.1).
func _find_net_butcher() -> Node:
	if _net_butcher_cached:
		return _net_butcher
	_net_butcher_cached = true
	for node: Node in get_tree().get_nodes_in_group(&"net_butcher"):
		if node.owns(self):
			_net_butcher = node
			break
	return _net_butcher

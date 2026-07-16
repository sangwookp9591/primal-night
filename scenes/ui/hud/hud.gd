class_name Hud
extends CanvasLayer

## 최소 HUD: 체력 / 스태미나 / 인벤토리 16칸 / 출혈 상태 / 감각 피드백(바람·소리·랩터 경보).
##
## 성능 규칙 (성능문서 6.1/6.2):
##   - 매 프레임 갱신하는 것은 ProgressBar.value 두 개와 감각 모델의 숫자 필드뿐이다
##     (문자열 조립·할당 없음, 성분 복사와 float 감산만 한다).
##   - 문자열은 상태가 실제로 바뀐 순간에만 만든다 (단계 라벨, 슬롯, 프롬프트).
##   - 슬롯은 인벤토리 changed 신호로만 다시 그린다. 매 프레임 폴링하지 않는다.
##   - 슬롯 Label 은 bind 시 16개를 한 번만 만들고 이후 재사용한다 (UI 재구성 금지).
##
## 표시 수치는 전부 데이터 리소스에서 생성한다. HUD 에 하드코딩하지 않는다 (설계서 5.6/15장).
##
## 감각 피드백 (설계서 5.4/12장): 숫자 격자 대신 바람 화살표, 최근 큰 소리 방향,
## 랩터 추격 경보를 보여준다. 디버그 격자(F4)와는 분리된 플레이 HUD 다.
## 판정 로직은 SenseIndicatorModel(res://scripts/senses/sense_indicator_model.gd)에
## 있고, 여기서는 그 상태를 읽어 그리기만 한다 (렌더 픽셀 검증은 하지 않는다).

const STAGE_HEALTHY: String = "양호"
const STAGE_HURT: String = "부상"
const STAGE_CRITICAL: String = "위독"

## 생존 수치 4종의 표시 이름 (설계서 5.1). 단계 문자열은 SurvivalStats 가 소유한다.
const STAT_NAMES: Dictionary = {
	&"temperature": "체온", &"water": "수분", &"food": "포만", &"fatigue": "피로",
}

@onready var _health_stage: Label = $Root/Column/HealthRow/HealthStage
@onready var _health_bar: ProgressBar = $Root/Column/HealthRow/HealthBar
@onready var _bleeding: Label = $Root/Column/HealthRow/Bleeding
@onready var _stamina_bar: ProgressBar = $Root/Column/StaminaRow/StaminaBar
@onready var _slots: GridContainer = $Root/Column/Slots
@onready var _prompt: Label = $Root/Column/Prompt
@onready var _wind_arrow: Label = $Root/Column/SenseRow/WindArrow
@onready var _sound_arrow: Label = $Root/Column/SenseRow/SoundArrow
@onready var _raptor_alert: Label = $Root/Column/SenseRow/RaptorAlert
@onready var _stat_labels: Dictionary = {
	&"temperature": $Root/Column/StatsRow/Temperature,
	&"water": $Root/Column/StatsRow/Water,
	&"food": $Root/Column/StatsRow/Food,
	&"fatigue": $Root/Column/StatsRow/Fatigue,
}

## 마지막으로 그린 단계. 단계가 바뀐 프레임에만 문자열을 만든다 (성능 규칙).
var _stat_stages: Dictionary = {}
var _player: Player = null
var _game_data: Node = null
var _slot_labels: Array[Label] = []
var _last_stage: String = ""
var _indicator_model: SenseIndicatorModel = SenseIndicatorModel.new()
var _smell_grid: SmellGrid = null
var _raptors_connected: bool = false
## 화살표 회전은 방향이 실제로 바뀐 프레임에만 만진다 (set_rotation 은 같은 값에도
## transform 을 더럽힌다). 문자열 단계 라벨의 _last_stage 와 같은 규칙.
var _last_wind_direction: Vector2 = Vector2.INF
var _last_sound_direction: Vector2 = Vector2.INF
## 랩터가 아직 없는(또는 늦게 생기는) 화면에서 매 프레임 그룹 조회를 반복하지
## 않는다 — 이미 만료된 값으로 시작해 첫 프레임엔 즉시 시도하고, 실패하면 주기마다만
## 재시도한다 (성능문서 6.1).
const RAPTOR_SCAN_INTERVAL_SECONDS: float = 2.0
var _raptor_scan_elapsed: float = RAPTOR_SCAN_INTERVAL_SECONDS

func _ready() -> void:
	_game_data = get_node("/root/GameData")
	set_process(false)
	# 씬에 그냥 놓았을 때는 스스로 플레이어를 찾는다 (1회 탐색).
	var found: Node = get_tree().get_first_node_in_group("player")
	if found != null:
		bind(found as Player)

func bind(player: Player) -> void:
	if player == null or _player == player:
		return
	_player = player

	_slots.columns = mini(player.inventory.slot_count, 8)
	for i: int in range(player.inventory.slot_count):
		var label: Label = Label.new()
		label.custom_minimum_size = Vector2(48.0, 24.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_slots.add_child(label)
		_slot_labels.append(label)

	_health_bar.max_value = player.health.config.max_health
	_stamina_bar.max_value = player.stamina.config.max_stamina

	player.inventory.changed.connect(_refresh_slots)
	player.interactor.hold_changed.connect(_on_hold_changed)

	var event_bus: Node = get_node("/root/EventBus")
	event_bus.bleeding_started.connect(_on_bleeding_changed.bind(true))
	event_bus.bleeding_stopped.connect(_on_bleeding_changed.bind(false))
	event_bus.noise_emitted.connect(_on_noise_emitted)

	_refresh_slots()
	_refresh_stage()
	_refresh_stat_stages()
	set_process(true)

func _process(delta: float) -> void:
	# 매 프레임 하는 일은 이 두 줄이 전부다. 문자열도 할당도 없다.
	_health_bar.value = _player.health.current_health
	_stamina_bar.value = _player.stamina.current_stamina

	# 단계 라벨은 단계가 실제로 바뀐 프레임에만 문자열을 만진다.
	var stage: String = stage_label_for_health()
	if stage != _last_stage:
		_last_stage = stage
		_health_stage.text = stage

	# 4수치도 단계가 바뀐 프레임에만 문자열을 만진다 (float 비교 4번이 전부다).
	_refresh_stat_stages()

	_ensure_raptors_connected(delta)
	var grid: SmellGrid = _find_smell_grid()
	if grid != null:
		_indicator_model.set_wind(grid.wind_direction, grid.wind_strength)
	_indicator_model.update(delta)
	_refresh_sense_indicators()

## 숫자 나열보다 단계 표시 (설계서 10.1). 경계값은 SurvivalConfig 에서 온다.
func stage_label_for_health() -> String:
	if _player == null:
		return ""

	var config: SurvivalConfig = _player.health.config
	var ratio: float = _player.health.current_health / config.max_health
	if ratio < config.health_critical_ratio:
		return STAGE_CRITICAL
	if ratio < config.health_hurt_ratio:
		return STAGE_HURT
	return STAGE_HEALTHY

## 생존 수치 4종은 숫자가 아니라 단계로만 보여준다 (설계서 5.1/10.1).
func stat_stage_text(stat: StringName) -> StringName:
	return _stat_stages.get(stat, &"")


func _refresh_stat_stages() -> void:
	if _player == null:
		return
	for stat: StringName in SurvivalStats.STATS:
		var stage: StringName = _player.stats.stage_of(stat)
		if _stat_stages.get(stat, &"") == stage:
			continue
		_stat_stages[stat] = stage
		(_stat_labels[stat] as Label).text = "%s %s" % [STAT_NAMES[stat], stage]


func slot_text(index: int) -> String:
	if index < 0 or index >= _slot_labels.size():
		return ""
	return _slot_labels[index].text

func bleeding_visible() -> bool:
	return _bleeding.visible

func _refresh_slots() -> void:
	for i: int in range(_slot_labels.size()):
		var slot: Dictionary = _player.inventory.get_slot(i)
		if slot.is_empty():
			_slot_labels[i].text = ""
			continue
		# 표시 이름은 ItemData 에서 온다. HUD 는 이름을 알지 못한다.
		var item: ItemData = _game_data.get_item(slot["id"])
		if item == null:
			_slot_labels[i].text = ""
			continue
		_slot_labels[i].text = "%s\n%d" % [item.display_name, int(slot["count"])]

func _refresh_stage() -> void:
	_last_stage = stage_label_for_health()
	_health_stage.text = _last_stage

func _on_bleeding_changed(target: Node, bleeding: bool) -> void:
	if target != _player:
		return
	_bleeding.visible = bleeding

func _on_hold_changed(ratio: float, label: String) -> void:
	if label.is_empty():
		_prompt.text = ""
		return
	_prompt.text = "%s  %d%%" % [label, int(ratio * 100.0)]

func _on_noise_emitted(position: Vector2, _radius: float, source: Node) -> void:
	if _player == null or source == _player:
		return
	_indicator_model.report_noise(position, _player.global_position)

func _find_smell_grid() -> SmellGrid:
	if _smell_grid == null or not is_instance_valid(_smell_grid):
		_smell_grid = SmellGrid.find_in(get_tree())
	return _smell_grid

## 랩터는 &"raptor" 그룹으로 찾는다 (player/smell_grid 와 같은 관례). 한 번 다 찾으면
## 다시 찾지 않고, 못 찾았을 때는 RAPTOR_SCAN_INTERVAL_SECONDS 주기로만 재시도한다.
func _ensure_raptors_connected(delta: float) -> void:
	if _raptors_connected:
		return
	_raptor_scan_elapsed += delta
	if _raptor_scan_elapsed < RAPTOR_SCAN_INTERVAL_SECONDS:
		return
	_raptor_scan_elapsed = 0.0
	var found: Array = get_tree().get_nodes_in_group(&"raptor")
	if found.is_empty():
		return
	for raptor: Raptor in found:
		raptor.state_changed.connect(_on_raptor_state_changed)
	_raptors_connected = true

func _on_raptor_state_changed(_previous_state: int, new_state: int) -> void:
	_indicator_model.set_raptor_chasing(new_state == Raptor.State.CHASE)

## 감각 표시 3종을 모델 상태로 갱신한다. 문자열은 만들지 않고, 회전은 방향이
## 바뀐 프레임에만 계산·할당한다.
func _refresh_sense_indicators() -> void:
	_wind_arrow.visible = _indicator_model.has_wind()
	if _wind_arrow.visible and _indicator_model.wind_direction != _last_wind_direction:
		_last_wind_direction = _indicator_model.wind_direction
		_wind_arrow.rotation = _last_wind_direction.angle()

	_sound_arrow.visible = _indicator_model.has_recent_sound()
	if _sound_arrow.visible:
		var sound_direction: Vector2 = _indicator_model.sound_direction()
		if sound_direction != _last_sound_direction:
			_last_sound_direction = sound_direction
			_sound_arrow.rotation = sound_direction.angle()

	_raptor_alert.visible = _indicator_model.raptor_alert

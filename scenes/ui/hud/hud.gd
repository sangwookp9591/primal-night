class_name Hud
extends CanvasLayer

## 최소 HUD: 체력 / 스태미나 / 인벤토리 8칸 / 출혈 상태.
##
## 성능 규칙 (성능문서 6.1/6.2):
##   - 매 프레임 갱신하는 것은 ProgressBar.value 두 개뿐이다 (문자열 조립·할당 없음).
##   - 문자열은 상태가 실제로 바뀐 순간에만 만든다 (단계 라벨, 슬롯, 프롬프트).
##   - 슬롯은 인벤토리 changed 신호로만 다시 그린다. 매 프레임 폴링하지 않는다.
##   - 슬롯 Label 은 bind 시 8개를 한 번만 만들고 이후 재사용한다 (UI 재구성 금지).
##
## 표시 수치는 전부 데이터 리소스에서 생성한다. HUD 에 하드코딩하지 않는다 (설계서 5.6/15장).

const STAGE_HEALTHY: String = "양호"
const STAGE_HURT: String = "부상"
const STAGE_CRITICAL: String = "위독"

@onready var _health_stage: Label = $Root/Column/HealthRow/HealthStage
@onready var _health_bar: ProgressBar = $Root/Column/HealthRow/HealthBar
@onready var _bleeding: Label = $Root/Column/HealthRow/Bleeding
@onready var _stamina_bar: ProgressBar = $Root/Column/StaminaRow/StaminaBar
@onready var _slots: GridContainer = $Root/Column/Slots
@onready var _prompt: Label = $Root/Column/Prompt

var _player: Player = null
var _game_data: Node = null
var _slot_labels: Array[Label] = []
var _last_stage: String = ""

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

	_slots.columns = player.inventory.slot_count
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

	_refresh_slots()
	_refresh_stage()
	set_process(true)

func _process(_delta: float) -> void:
	# 매 프레임 하는 일은 이 두 줄이 전부다. 문자열도 할당도 없다.
	_health_bar.value = _player.health.current_health
	_stamina_bar.value = _player.stamina.current_stamina

	# 단계 라벨은 단계가 실제로 바뀐 프레임에만 문자열을 만진다.
	var stage: String = stage_label_for_health()
	if stage != _last_stage:
		_last_stage = stage
		_health_stage.text = stage

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

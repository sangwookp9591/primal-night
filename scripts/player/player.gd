class_name Player
extends CharacterBody2D

const DEFAULT_CONFIG: PlayerConfig = preload("res://resources/player/player_config.tres")
const QUICK_CRAFT_PRIORITY: Array[StringName] = [
	&"craft_stone_knife",
	&"craft_torch",
	&"craft_bone_scraper",
	&"craft_noise_lure",
	&"craft_bait",
	&"craft_storage_cache",
	&"craft_drying_rack",
	&"craft_bedding",
	&"repair_outfit",
]
const FACING_VECTORS: Array[Vector2] = [
	Vector2.UP, Vector2(0.70710678, -0.70710678), Vector2.RIGHT,
	Vector2(0.70710678, 0.70710678), Vector2.DOWN,
	Vector2(-0.70710678, 0.70710678), Vector2.LEFT,
	Vector2(-0.70710678, -0.70710678),
]
const BloodTrailScript = preload("res://scripts/survival/blood_trail.gd")

## 이동 자세 — 소음 프로필 선택과 호스트 교차검증의 공통 어휘 (설계서 5.6/7.4).
## 세기 순서: CROUCH < WALK < RUN. NetMovement 가 이 순서로 위조 주장을 강등한다.
enum Stance { WALK, RUN, CROUCH }

@export var config: PlayerConfig = DEFAULT_CONFIG

## 생존 규칙은 컴포넌트가 소유한다. Player 는 입력과 이동만 안다 (설계서 9.2).
@onready var health: HealthComponent = $HealthComponent
@onready var stamina: StaminaComponent = $StaminaComponent
@onready var inventory: Inventory = $Inventory
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var interactor: Interactor = $Interactor
@onready var visual_rig: PlayerVisualRig = get_node_or_null("VisualRig") as PlayerVisualRig
## 체온·수분·포만·피로 (설계서 5.1). player.tscn 에 노출하되, 코드 생성 경로도 유지한다.
@onready var stats: SurvivalStats = get_node_or_null("SurvivalStats") as SurvivalStats
var injury: InjuryComponent = InjuryComponent.new()
var actions: ActionController = ActionController.new()

## 치료 중에는 양쪽 모두 이동이 제한된다 (설계서 5.2).
var movement_locked: bool = false
var bow_aiming: bool = false

## StealthZone(수풀)이 겹침으로 직접 설정한다 (설계서 5.6). Player 는 트리를 뒤지지 않는다.
var in_bush: bool = false

## 로컬 컨트롤러가 이번 틱에 고른 자세. NetMovement 가 이 값을 읽어 이동 의도에 실어
## 호스트로 보낸다 (원격 아바타는 이 필드를 직접 쓰지 않는다 — 자기 브랜치 입력만 반영).
var stance: int = Stance.WALK

## 호스트가 교차검증 후 확정한 자세 (설계서 7.4). 원격 아바타의 소음 판정은 클라이언트
## 주장이 아니라 이 값을 쓴다 (SmellGrid._emit_remote_player_noise). 로컬 아바타 자신의
## 소음은 이 필드를 거치지 않고 stance 를 바로 쓴다 — 자기 이동은 호스트에서 그대로 신뢰.
var last_validated_stance: int = Stance.WALK

## 이 아바타를 조종하는 peer id. 로컬 기계가 조종하지 않는 원격 아바타는
## 입력을 읽지 않는다 — 위치는 호스트 검증(NetMovement)과 스냅샷이 정한다 (설계서 7.2).
## 싱글플레이는 offline peer id(1) == 기본값이라 기존 흐름 그대로다 (설계서 9.3).
var controller_peer_id: int = 1

var _noise_radius: float = 0.0
var _noise_emit_elapsed: float = 0.0
var _event_bus: Node = null
var _noise_emitter: NoiseEmitter = NoiseEmitter.new()

func _ready() -> void:
	add_to_group("player")
	if stats == null:
		stats = SurvivalStats.new()
		stats.name = "SurvivalStats"
		add_child(stats)
	stats.config = health.config
	injury.name = "InjuryComponent"
	injury.config = health.config
	add_child(injury)
	actions.name = "ActionController"
	add_child(actions)
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
	var blood_trail := BloodTrailScript.new() as BloodTrail
	blood_trail.name = "BloodTrail"
	blood_trail.player = self
	add_child(blood_trail)

func _physics_process(delta: float) -> void:
	if controller_peer_id != multiplayer.get_unique_id():
		return
	if Input.is_action_just_pressed("quick_craft"):
		var recipe_id: StringName = select_quick_craft_recipe()
		if recipe_id != &"":
			_request_quick_craft(recipe_id)
	if Input.is_action_just_pressed("place_lure"):
		_request_place_lure()
	if Input.is_action_just_pressed("attack"):
		if equipment.get_equipped(&"main_hand") == &"bow":
			_request_bow_aim(true)
		else:
			_request_attack()
	if Input.is_action_just_released("attack") and bow_aiming:
		_request_bow_fire()
	var input_vector: Vector2 = Vector2.ZERO if movement_locked else _get_input_vector()
	var moving: bool = not input_vector.is_zero_approx()
	var crouching: bool = Input.is_action_pressed("crouch")
	# 스태미나가 없으면 run 을 누르고 있어도 달릴 수 없다. 웅크리면 달리지 않는다 (은신 우선).
	var running: bool = moving and not crouching and Input.is_action_pressed("run") and stamina.can_run()
	stance = Stance.CROUCH if crouching else (Stance.RUN if running else Stance.WALK)
	var speed: float = (config.crouch_speed if crouching else \
		(config.run_speed if running else config.walk_speed)) * injury.movement_multiplier()
	if bow_aiming:
		speed *= NetCombat.BOW_AIM_MOVE_MULTIPLIER

	stamina.update(running, moving, delta, stats.fatigue_ratio(), stats.water_wellness(),
		stats.wet_run_drain_penalty())

	velocity = input_vector * speed
	move_and_slide()
	_refresh_visual_animation()

	if not moving:
		_noise_radius = 0.0
		_noise_emit_elapsed = 0.0
		return

	var profile: NoiseProfile = get_noise_profile_for_stance(stance)
	_noise_radius = profile.radius * clothing_noise_multiplier()
	_noise_emit_elapsed += delta
	if _noise_emit_elapsed >= config.noise_emit_interval:
		_noise_emit_elapsed = 0.0
		if _event_bus != null:
			_noise_emitter.emit_profile(_event_bus, profile, global_position, self, -1.0, true,
				clothing_noise_multiplier())


func _refresh_visual_animation() -> void:
	if visual_rig != null:
		visual_rig.update_from_velocity(velocity, stance)

func get_noise_radius() -> float:
	return _noise_radius

func equipped_outfit() -> WearableData:
	if equipment == null:
		return null
	var item_id := equipment.get_equipped(&"outfit")
	if item_id == &"":
		return null
	return get_node("/root/GameData").get_item(item_id) as WearableData

func clothing_noise_multiplier() -> float:
	var outfit := equipped_outfit()
	if outfit == null:
		return 1.0
	# 젖은 옷은 급한 움직임에서 더 크게 철벅인다.
	return maxf(0.1, 1.0 + outfit.noise_modifier + stats.wetness * 0.22)

func clothing_smell_multiplier() -> float:
	var outfit := equipped_outfit()
	return maxf(0.0, 1.0 + (outfit.smell_modifier if outfit != null else 0.0))

## 자세별 소음 프로필. 로컬(자기 입력 기준)과 원격(호스트 검증 자세 기준,
## SmellGrid._emit_remote_player_noise) 이 이 표를 공유해 판정이 갈라지지 않는다.
## 수풀에서 달리면 헤치는 소리가 우선한다. 그다음은 웅크림(항상 조용), 그다음 걷기/달리기.
## 수풀 여부는 자기 상태(in_bush — StealthZone 이 겹침으로 설정)에서 직접 읽는다.
func get_noise_profile_for_stance(for_stance: int) -> NoiseProfile:
	if in_bush and for_stance == Stance.RUN:
		return config.bush_run_noise_profile
	if for_stance == Stance.CROUCH:
		return config.crouch_noise_profile
	return config.run_noise_profile if for_stance == Stance.RUN else config.walk_noise_profile

## 자세별 최대 이동 속도. NetMovement 가 주장된 자세를 실측 속도와 교차검증할 때 쓴다.
func max_speed_for_stance(for_stance: int) -> float:
	match for_stance:
		Stance.CROUCH:
			return config.crouch_speed * injury.movement_multiplier()
		Stance.RUN:
			return config.run_speed * injury.movement_multiplier()
		_:
			return config.walk_speed * injury.movement_multiplier()

func _get_input_vector() -> Vector2:
	var horizontal: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vertical: float = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var raw: Vector2 = Vector2(horizontal, vertical)
	if raw.is_zero_approx():
		return Vector2.ZERO

	var iso: Vector2 = Vector2(raw.x - raw.y, (raw.x + raw.y) * 0.5)
	return iso.normalized()

func _request_quick_craft(recipe_id: StringName) -> void:
	for node in get_tree().get_nodes_in_group(&"net_crafting"):
		if node.has_method("request"):
			node.request(recipe_id, self)
			return


func _request_place_lure() -> void:
	for node in get_tree().get_nodes_in_group(&"net_pickup"):
		if node.has_method("request_place_noise_lure_for"):
			node.request_place_noise_lure_for(self)
			return

func _request_attack() -> void:
	for node in get_tree().get_nodes_in_group(&"net_combat"):
		if node.has_method("request_attack"):
			node.request_attack(self, facing_direction())
			return
	push_warning("Player: 공격 시스템을 찾을 수 없습니다.")

func _request_bow_aim(active: bool) -> void:
	for node in get_tree().get_nodes_in_group(&"net_combat"):
		if node.has_method("request_bow_aim"):
			node.request_bow_aim(self, active, facing_direction())
			return

func _request_bow_fire() -> void:
	for node in get_tree().get_nodes_in_group(&"net_combat"):
		if node.has_method("request_bow_fire"):
			node.request_bow_fire(self, facing_direction())
			return

func set_bow_aim_feedback(active: bool, direction: Vector2) -> void:
	bow_aiming = active
	if visual_rig == null:
		return
	var line := visual_rig.get_node_or_null("AimPlaceholder") as Line2D
	if line == null:
		line = Line2D.new()
		line.name = "AimPlaceholder"
		line.width = 2.0
		line.default_color = Color(0.93, 0.76, 0.3, 0.72)
		visual_rig.add_child(line)
	line.points = PackedVector2Array([Vector2.ZERO, direction.normalized() * 72.0])
	line.visible = active

func facing_direction() -> Vector2:
	if visual_rig == null or visual_rig.base_body == null:
		return Vector2.DOWN
	return FACING_VECTORS[visual_rig.base_body.last_direction]

func play_attack_feedback(direction: Vector2) -> void:
	if visual_rig == null:
		return
	var tween := create_tween()
	tween.tween_property(visual_rig, "position", direction.normalized() * 10.0, 0.08)
	tween.tween_property(visual_rig, "position", Vector2.ZERO, 0.12)


func request_consume(item_id: StringName) -> void:
	for node in get_tree().get_nodes_in_group(&"net_survival"):
		if node.has_method("request_consume_for") and node.owns(self):
			node.request_consume_for(self, item_id)
			return
	# 독립 UI/플레이어 장면도 같은 진입점을 쓸 수 있게 하는 오프라인 폴백.
	# 실제 게임의 멀티플레이 브랜치에서는 위 NetSurvival 호스트 경로가 항상 우선한다.
	var item := get_node("/root/GameData").get_item(item_id) as ItemData
	ConsumeAction.consume(self, item)


## 로컬 입력 편의를 위한 후보 선택만 한다. 최종 재료·무게·슬롯 판정과 소비는
## 기존 NetCrafting 호스트 권위 경로가 담당한다.
func select_quick_craft_recipe() -> StringName:
	var game_data: Node = get_node("/root/GameData")
	for recipe_id: StringName in QUICK_CRAFT_PRIORITY:
		var recipe: RecipeData = game_data.get_recipe(recipe_id)
		if recipe == null:
			continue
		if recipe.repairs_outfit and (equipment == null or not equipment.can_repair_outfit()):
			continue
		var has_all_ingredients := true
		for item_id: Variant in recipe.ingredients:
			if not inventory.has_item(StringName(item_id), int(recipe.ingredients[item_id])):
				has_all_ingredients = false
				break
		if has_all_ingredients:
			return recipe_id
	return &""

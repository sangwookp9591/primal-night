extends GutTest

## HUD: 체력 / 스태미나 / 인벤토리 16칸 / 출혈 상태.
## ★ 표시 수치는 반드시 데이터 리소스에서 생성한다. UI 에 하드코딩 금지 (설계서 5.6/15장).
## ★ 숫자 나열보다 단계 표시 (설계서 10.1).

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const HudScene: PackedScene = preload("res://scenes/ui/hud/hud.tscn")
const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")

var _game_data: Node = null

func before_each() -> void:
	_game_data = get_node("/root/GameData")

func _spawn() -> Array:
	var world: Node2D = add_child_autofree(Node2D.new())
	var clock: SessionClock = SessionClock.new()
	clock.name = "SessionClock"
	world.add_child(clock)
	clock.stop()
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var hud: Hud = HudScene.instantiate()
	world.add_child(hud)
	await wait_physics_frames(1)
	hud.bind(player)
	return [player, hud, clock]


func test_time_text_follows_session_clock_signal() -> void:
	var spawned: Array = await _spawn()
	var hud: Hud = spawned[1]
	var clock: SessionClock = spawned[2]

	clock.apply_replicated(2, 480.0, false)

	assert_string_contains(hud.time_text(), "2일")
	assert_string_contains(hud.time_text(), "밤")

func test_shows_sixteen_inventory_slots() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]

	assert_eq(player.inventory.slot_count, 16, "전제: 인벤토리는 16칸")
	for i: int in range(16):
		assert_eq(hud.slot_text(i), "", "빈 슬롯은 비어 보여야 한다")

func test_target_prompt_follows_current_world_item_and_hides_out_of_range() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]
	var item: WorldItem = WorldItemScene.instantiate()
	item.item_id = &"wood"
	item.count = 2
	item.position = Vector2(16.0, 0.0)
	player.get_parent().add_child(item)
	await wait_physics_frames(2)

	assert_eq(hud.target_prompt_text(), item.get_prompt())
	assert_not_null(item.get_node_or_null("InteractionTargetMarker"),
		"선택된 월드 아이템 위에 단순 마커가 붙어야 한다")

	item.position = Vector2(400.0, 0.0)
	await wait_physics_frames(2)

	assert_eq(hud.target_prompt_text(), "")

## ★ 슬롯 표시는 ItemData.display_name 에서 생성된다. HUD 에 이름을 적어두지 않는다.
func test_slot_text_comes_from_item_data_not_from_the_hud() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]
	var stone: ItemData = _game_data.get_item(&"stone")

	player.inventory.add_item(&"stone", 4)

	var text: String = hud.slot_text(0)
	assert_string_contains(text, stone.display_name, "표시 이름은 ItemData 에서 와야 한다")
	assert_string_contains(text, "4", "수량이 표시되어야 한다")

## 데이터의 표시 이름을 바꾸면 HUD 도 따라 바뀌어야 한다 (하드코딩이면 안 따라온다).
func test_hud_follows_the_data_when_display_name_changes() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]
	var stone: ItemData = _game_data.get_item(&"stone")
	var original: String = stone.display_name
	stone.display_name = "조약돌"

	player.inventory.add_item(&"stone", 1)
	var text: String = hud.slot_text(0)

	stone.display_name = original  # 전역 리소스이므로 되돌린다
	assert_string_contains(text, "조약돌", "HUD 는 데이터를 그대로 읽어야 한다 (하드코딩 금지)")

## ★ 설계서 10.1: 숫자 나열보다 단계 표시. 경계값은 SurvivalConfig 에서 온다.
func test_health_is_shown_as_a_stage_not_a_bare_number() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]
	var config: SurvivalConfig = player.health.config

	assert_eq(hud.stage_label_for_health(), "양호", "가득 찬 체력은 양호")

	player.health.current_health = config.max_health * (config.health_hurt_ratio - 0.01)
	assert_eq(hud.stage_label_for_health(), "부상", "부상 경계 아래면 부상")

	player.health.current_health = config.max_health * (config.health_critical_ratio - 0.01)
	assert_eq(hud.stage_label_for_health(), "위독", "위독 경계 아래면 위독")

func test_bleeding_indicator_follows_the_bleeding_state() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]

	assert_false(hud.bleeding_visible(), "출혈 중이 아니면 표시하지 않는다")

	player.health.start_bleeding()
	await wait_physics_frames(1)
	assert_true(hud.bleeding_visible(), "출혈 중이면 표시해야 한다")

	player.health.stop_bleeding()
	await wait_physics_frames(1)
	assert_false(hud.bleeding_visible(), "지혈되면 표시를 끈다")

## HUD 는 인벤토리 changed 신호로 갱신한다 (매 프레임 폴링 금지, 성능문서 6.2).
func test_slots_refresh_on_the_inventory_changed_signal() -> void:
	var spawned: Array = await _spawn()
	var player: Player = spawned[0]
	var hud: Hud = spawned[1]

	player.inventory.add_item(&"wood", 2)

	# 프레임을 돌리지 않았는데도 이미 갱신되어 있어야 한다 = 신호 기반이다.
	var wood: ItemData = _game_data.get_item(&"wood")
	assert_string_contains(hud.slot_text(0), wood.display_name, "changed 신호를 받아 즉시 갱신되어야 한다")

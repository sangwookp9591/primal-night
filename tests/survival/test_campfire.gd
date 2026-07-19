extends GutTest

## 돌 + 나무로 지정 자리에 모닥불을 설치·점화한다 (설계서 5.8: 자유 건축 금지).
## campfire_lit 의 radius 는 T4 의 랩터가 회피 판단에 쓴다.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CampfireSiteScene: PackedScene = preload("res://scenes/props/campfire_site.tscn")
const CampfireConfigScript = preload("res://scripts/props/campfire_config.gd")

var _event_bus: Node = null

func before_each() -> void:
	_event_bus = get_node("/root/EventBus")

func _make_config() -> CampfireConfig:
	var config: CampfireConfig = CampfireConfigScript.new()
	config.light_radius = 220.0
	config.fuel_seconds = 10.0
	config.stone_cost = 3
	config.wood_cost = 2
	config.build_seconds = 1.0
	return config

func _spawn(config: CampfireConfig, site_offset: Vector2) -> Array:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	world.add_child(player)
	var site: CampfireSite = CampfireSiteScene.instantiate()
	site.config = config
	site.position = site_offset
	world.add_child(site)
	await wait_physics_frames(2)
	return [player, site]

func _stock(player: Player, config: CampfireConfig) -> void:
	player.inventory.add_item(&"stone", config.stone_cost)
	player.inventory.add_item(&"wood", config.wood_cost)

func test_cannot_build_without_materials() -> void:
	var config: CampfireConfig = _make_config()
	var spawned: Array = await _spawn(config, Vector2(24.0, 0.0))
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]

	assert_false(site.can_interact(player), "재료가 없으면 설치할 수 없다")
	assert_null(player.interactor.find_target(), "재료가 없으면 대상으로 잡히지 않는다")

func test_cannot_build_with_only_stone() -> void:
	var config: CampfireConfig = _make_config()
	var spawned: Array = await _spawn(config, Vector2(24.0, 0.0))
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]
	player.inventory.add_item(&"stone", config.stone_cost)

	assert_false(site.can_interact(player), "나무가 없으면 설치할 수 없다")

func test_site_becomes_a_target_once_materials_are_held() -> void:
	var config: CampfireConfig = _make_config()
	var spawned: Array = await _spawn(config, Vector2(24.0, 0.0))
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]
	_stock(player, config)

	assert_true(site.can_interact(player), "돌과 나무가 있으면 설치할 수 있다")
	assert_eq(player.interactor.find_target(), site, "설치 자리를 대상으로 찾아야 한다")
	assert_gt(site.get_hold_seconds(), 0.0, "설치는 길게 눌러야 한다")

## ★ 점화 시 campfire_lit(campfire, position, radius) 를 발신한다.
func test_building_consumes_materials_lights_the_fire_and_emits_campfire_lit() -> void:
	var config: CampfireConfig = _make_config()
	var site_position: Vector2 = Vector2(24.0, 0.0)
	var spawned: Array = await _spawn(config, site_position)
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]
	_stock(player, config)
	watch_signals(_event_bus)

	player.interactor.begin()
	player.interactor._process(config.build_seconds + 0.01)

	assert_not_null(site.campfire, "설치 자리에 모닥불이 생겨야 한다")
	assert_true(site.campfire.is_lit, "설치하면 점화되어야 한다")
	assert_eq(player.inventory.count_of(&"stone"), 0, "돌을 소비해야 한다")
	assert_eq(player.inventory.count_of(&"wood"), 0, "나무를 소비해야 한다")

	assert_signal_emitted(_event_bus, "campfire_lit", "campfire_lit 이 발신되어야 한다")
	var params: Array = get_signal_parameters(_event_bus, "campfire_lit", 0)
	assert_eq(params[0], site.campfire, "모닥불 노드가 전달되어야 한다")
	assert_eq(params[1], site_position, "지정 자리에 스냅되어야 한다 (자유 건축 금지)")
	assert_eq(params[2], config.light_radius, "radius 는 데이터 리소스에서 온다")

func test_materials_are_not_consumed_if_the_build_is_cancelled() -> void:
	var config: CampfireConfig = _make_config()
	var spawned: Array = await _spawn(config, Vector2(24.0, 0.0))
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]
	_stock(player, config)

	player.interactor.begin()
	player.interactor._process(config.build_seconds * 0.5)
	player.interactor.cancel()

	assert_null(site.campfire, "취소하면 설치되지 않는다")
	assert_eq(player.inventory.count_of(&"stone"), config.stone_cost, "취소하면 돌을 소비하지 않는다")
	assert_eq(player.inventory.count_of(&"wood"), config.wood_cost, "취소하면 나무를 소비하지 않는다")

func test_a_built_site_accepts_fuel_without_building_a_second_fire() -> void:
	var config: CampfireConfig = _make_config()
	var spawned: Array = await _spawn(config, Vector2(24.0, 0.0))
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]
	_stock(player, config)
	player.interactor.begin()
	player.interactor._process(config.build_seconds + 0.01)

	_stock(player, config)

	var original_fire := site.campfire
	assert_true(site.can_interact(player), "완성된 모닥불은 나무를 연료로 받을 수 있다")
	assert_eq(site.cook_kind(player), &"fuel_dry")
	assert_eq(site.campfire, original_fire, "연료 상호작용은 두 번째 모닥불을 만들지 않는다")

## 연료가 떨어지면 꺼지고 campfire_extinguished 를 발신한다.
func test_campfire_burns_out_when_fuel_runs_dry() -> void:
	var config: CampfireConfig = _make_config()
	var spawned: Array = await _spawn(config, Vector2(24.0, 0.0))
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]
	_stock(player, config)
	player.interactor.begin()
	player.interactor._process(config.build_seconds + 0.01)
	var campfire: Campfire = site.campfire
	watch_signals(_event_bus)

	assert_eq(campfire.fuel_remaining, config.fuel_seconds, "점화 시 연료가 가득 차야 한다")

	campfire._process(config.fuel_seconds * 0.5)
	assert_true(campfire.is_lit, "연료가 남아 있으면 계속 탄다")

	campfire._process(config.fuel_seconds * 0.5 + 0.01)

	assert_false(campfire.is_lit, "연료가 떨어지면 꺼져야 한다")
	assert_eq(campfire.fuel_remaining, 0.0, "연료는 음수가 되지 않는다")
	assert_signal_emitted(_event_bus, "campfire_extinguished", "campfire_extinguished 가 발신되어야 한다")
	var params: Array = get_signal_parameters(_event_bus, "campfire_extinguished", 0)
	assert_eq(params[0], campfire, "꺼진 모닥불 노드가 전달되어야 한다")

func test_radius_comes_from_the_data_resource() -> void:
	var config: CampfireConfig = _make_config()
	config.light_radius = 333.0
	var spawned: Array = await _spawn(config, Vector2(24.0, 0.0))
	var player: Player = spawned[0]
	var site: CampfireSite = spawned[1]
	_stock(player, config)

	player.interactor.begin()
	player.interactor._process(config.build_seconds + 0.01)

	assert_eq(site.campfire.get_radius(), 333.0, "반경은 데이터 리소스에서 나온다 (하드코딩 금지)")

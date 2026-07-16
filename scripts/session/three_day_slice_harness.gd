extends SceneTree

## W6 압축 3일 통합 절편: 실제 main에서 day 경계가 1→2→3 순서로 진행되는 동안
## 기존 모닥불·다리 열상·인벤토리 상태가 시간 모델에 의해 초기화되지 않는지 판정한다.

const MainScene: PackedScene = preload("res://scenes/main.tscn")


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var main: Node2D = MainScene.instantiate()
	get_root().add_child(main)
	await physics_frame
	await physics_frame

	var clock: SessionClock = main.get_node("SessionClock")
	var player: Player = main.get_node("Player")
	var site: CampfireSite = main.get_node("SurvivalDemo/CampfireSite")
	var days: Array[int] = []
	clock.day_changed.connect(func(day: int) -> void: days.append(day))

	player.inventory.add_item(&"bandage", 2)
	if not player.injury.apply_replicated(&"leg", &"laceration"):
		_fail("다리 열상 전제 구성 실패")
		return
	site.build_and_light()
	clock.speed_multiplier = 1200.0

	for frame: int in range(180):
		if clock.current_day == 3:
			break
		await physics_frame

	var ok: bool = days == [2, 3] \
		and clock.current_day == 3 and not clock.is_expired() \
		and site.campfire != null and site.campfire.is_lit \
		and player.injury.has_leg_laceration() \
		and player.inventory.count_of(&"bandage") == 2
	if not ok:
		_fail("days=%s day=%d fire=%s injury=%s bandage=%d" % [
			days, clock.current_day,
			site.campfire != null and site.campfire.is_lit,
			player.injury.has_leg_laceration(), player.inventory.count_of(&"bandage")])
		return

	print("THREE_DAY_SLICE_OK days=%s fire=true injury=true bandage=2" % [days])
	quit(0)


func _fail(reason: String) -> void:
	push_error("THREE_DAY_SLICE_FAILED %s" % reason)
	quit(1)

extends SceneTree

## ★ 2주 차 목표 장면 전 구간 통합 하네스 — W2-T5 (개발 빌드 전용, 게임 코드 아님).
## 실행: /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s scripts/net/two_player_goal_scene_harness.gd
##
## 사용자가 정의한 2주 말 성공 기준을 하나의 실행으로 잇는다:
##   호스트가 방 생성 → (친구 초대는 Steam 몫 — 로컬 참가로 대체)
##   → 두 명이 작은 계곡 탐색 (둘 다 이동, 양방향 위치 복제)
##   → 한 명이 부상 (변조 피해량은 호스트가 클램프, 출혈 시작·복제)
##   → 랩터가 냄새를 추적 (호스트 랩터: 배회 → 조사 → 추격, 클라이언트로 상태 복제)
##   → 동료가 붕대로 치료 (월드 붕대 획득 → 호스트 확정 → 냄새 정지)
##   → 함께 모닥불로 탈출 (클라이언트가 재료 수집·설치 의도 → 호스트 확정·복제,
##     ★한 명만 보호되면 랩터는 물러나지 않고 노출된 동료를 추격한다★
##     → 둘 다 불 반경 안일 때 비로소 물러난다)
##   → 에필로그: 재접속 — 인벤토리·상태 복원, 총합 불변, 재접속 후 의도 동작.
##
## 결정적이어야 한다 (WEEK1_VERIFICATION.md B-01): 랩터 RNG 고정 seed,
## 입력·물리 기반 이동, 단계별 로그, 성공 시 exit 0 / 실패 시 exit 1.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")
const RAPTOR_RNG_SEED: int = 3

## 로그 타임스탬프 기준점 — 수동 프레임 부기 대신 엔진 물리 프레임 카운터에서 파생한다.
var _epoch_physics_frames: int = 0
var _campfire_lit_count: int = 0
var _blood_smell_count: int = 0


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_epoch_physics_frames = Engine.get_physics_frames()

	# ── phase 0: 두 '기계'에 main.tscn 로드 + W2 전체 배선 관문 ──
	_log("--- phase 0: 호스트/클라이언트 기계 로드 + 배선 관문 ---")
	var host_root: Node = _make_machine("HostMachine")
	var client_root: Node = _make_machine("ClientMachine")
	var host_main: Node2D = host_root.get_node("Main")
	var client_main: Node2D = client_root.get_node("Main")
	for required: String in ["NetSession", "NetMovement", "Players", "Player", "NetPickup",
			"NetSurvival", "NetCampfire", "NetResync", "SmellGrid", "Raptor",
			"SurvivalDemo/CampfireSite", "SurvivalDemo/Bandage"]:
		if host_main.get_node_or_null(required) == null:
			return _fail("main.tscn 에 %s 가 없다 — W2 배선 누락" % required)
	var host_session: SessionService = host_main.get_node("NetSession")
	var client_session: SessionService = client_main.get_node("NetSession")
	var host_player: Player = host_main.get_node("Player")
	var host_raptor: Raptor = host_main.get_node("Raptor")
	var client_raptor: Raptor = client_main.get_node("Raptor")
	var client_survival: NetSurvival = client_main.get_node("NetSurvival")
	# 모닥불 자리·반경은 씬과 데이터 리소스에서 읽는다 — 배치·수치가 바뀌어도 하네스가 따라간다.
	var host_site: CampfireSite = host_main.get_node("SurvivalDemo/CampfireSite")
	var fire_position: Vector2 = host_site.global_position
	var fire_radius: float = host_site.config.light_radius

	var event_bus: Node = get_root().get_node("EventBus")
	event_bus.campfire_lit.connect(
		func(_campfire: Node, position: Vector2, radius: float) -> void:
			_campfire_lit_count += 1
			_log("campfire_lit #%d at %s radius %.0f" % [_campfire_lit_count, position, radius]))
	event_bus.smell_emitted.connect(
		func(_position: Vector2, _strength: float, kind: StringName) -> void:
			if kind == &"blood":
				_blood_smell_count += 1)
	host_raptor.state_changed.connect(func(prev: int, next: int) -> void:
		_log("host raptor: %s -> %s (raptor=%s)" % [Raptor.STATE_NAMES[prev],
			Raptor.STATE_NAMES[next], host_raptor.global_position.snapped(Vector2.ONE)]))

	# ── phase 1: 호스트가 방 생성 → 친구 참가 (Steam 초대는 로컬 참가로 대체) ──
	_log("--- phase 1: 방 생성 + 참가 ---")
	if host_session.host_session() != OK:
		return _fail("host_session 실패")
	var port: int = (host_main.get_node("NetMovement") as NetMovement).config.port
	if client_session.join_session("127.0.0.1:%d" % port) != OK:
		return _fail("join_session 실패")
	if not await _wait_until(func() -> bool: return host_session.get_players().size() == 2, 10.0):
		return _fail("호스트가 참가를 관측하지 못했다")
	var client_id: StringName = client_session.get_local_player_id()
	var avatar_path: NodePath = NodePath("Players/%s" % client_id)
	if not await _wait_until(func() -> bool:
			return host_main.has_node(avatar_path) and client_main.has_node(avatar_path), 10.0):
		return _fail("클라이언트 아바타가 양쪽에 스폰되지 않았다")
	var host_view_client: Player = host_main.get_node(avatar_path)
	var client_avatar: Player = client_main.get_node(avatar_path)
	var client_view_host: Player = client_main.get_node("Player")
	_log("접속 완료. client_id=%s" % client_id)

	# ── phase 2: 두 명이 작은 계곡 탐색 — 둘 다 이동, 양방향 복제 ──
	_log("--- phase 2: 2인 계곡 탐색 (둘 다 이동) ---")
	var host_start: Vector2 = host_player.global_position
	var client_start: Vector2 = client_avatar.global_position
	# 같은 입력을 양쪽 로컬 아바타가 읽는다 — 두 명이 나란히 남쪽 평지로 걷는다.
	if not await _walk_until(client_avatar, client_start + Vector2(0.0, 120.0), 20.0):
		return _fail("클라이언트 아바타가 탐색 이동을 완료하지 못했다")
	if host_player.global_position.distance_to(host_start) < 90.0:
		return _fail("호스트가 함께 이동하지 않았다 (%.0fpx)" % host_player.global_position.distance_to(host_start))
	# 양방향 위치 복제: 호스트가 보는 클라이언트, 클라이언트가 보는 호스트.
	if not await _wait_until(func() -> bool:
			return host_view_client.global_position.distance_to(client_avatar.global_position) < 24.0 \
				and client_view_host.global_position.distance_to(host_player.global_position) < 24.0, 10.0):
		return _fail("탐색 이동이 양방향으로 복제되지 않았다")
	_log("탐색 완료: host=%s client=%s (양방향 복제 수렴)" % [
		host_player.global_position.snapped(Vector2.ONE), client_avatar.global_position.snapped(Vector2.ONE)])

	# ── phase 3: 한 명이 부상 — 변조 피해량 10000 주장 → 호스트 클램프 → 출혈 복제 ──
	_log("--- phase 3: 클라이언트 부상 (출혈 시작) ---")
	client_survival.request_hurt_for(client_avatar, 10000.0)
	if not await _wait_until(func() -> bool: return host_view_client.health.is_bleeding, 5.0):
		return _fail("호스트가 부상 의도를 확정하지 않았다")
	if not host_view_client.health.is_alive():
		return _fail("변조 피해량이 클램프되지 않았다 (즉사)")
	if not await _wait_until(func() -> bool: return client_avatar.health.is_bleeding, 5.0):
		return _fail("출혈 상태가 클라이언트로 복제되지 않았다")
	_log("부상 확정: health=%.1f bleeding=true (클램프 적용)" % host_view_client.health.current_health)

	# ── phase 4: 랩터가 냄새를 추적 — 배회 → 조사 → 추격 (호스트 AI) ──
	_log("--- phase 4: 랩터 냄새 추적 대기 ---")
	if not await _wait_until(func() -> bool:
			return host_raptor.state != Raptor.State.WANDER, 40.0, _report_raptor):
		return _fail("랩터가 조사로 전환하지 않았다")
	if host_raptor.state != Raptor.State.INVESTIGATE:
		return _fail("조사가 아니라 %s 로 전환했다" % host_raptor.get_state_name())
	if not await _wait_until(func() -> bool:
			return host_raptor.state == Raptor.State.CHASE, 60.0, _report_raptor):
		return _fail("랩터가 추격으로 전환하지 않았다")
	if not await _wait_until(func() -> bool: return client_raptor.state == Raptor.State.CHASE, 5.0):
		return _fail("추격 상태가 클라이언트 랩터로 복제되지 않았다")
	_log("추격 진입: raptor=%s (클라이언트 복제 확인)" % host_raptor.global_position.snapped(Vector2.ONE))

	# ── phase 5: 동료가 붕대로 치료 — 월드 붕대 획득 → 홀드 → 호스트 확정 → 냄새 정지 ──
	_log("--- phase 5: 호스트가 월드 붕대 획득 후 치료 ---")
	var world_bandage: WorldItem = host_main.get_node("SurvivalDemo/Bandage")
	host_player.global_position = world_bandage.global_position
	world_bandage.interact(host_player)
	if host_player.inventory.count_of(&"bandage") < 1:
		return _fail("호스트가 월드 붕대를 줍지 못했다")
	host_player.global_position = host_view_client.global_position + Vector2(-40.0, 0.0)
	await physics_frame
	await physics_frame
	host_player.interactor.begin()
	if host_player.interactor.current_target == null:
		return _fail("호스트가 출혈 중인 동료의 HealTarget 을 잡지 못했다")
	if not await _wait_until(func() -> bool: return client_avatar.movement_locked, 3.0):
		return _fail("치료 중 원격 환자의 이동이 잠기지 않았다")
	if not await _wait_until(func() -> bool: return not host_view_client.health.is_bleeding, 8.0):
		return _fail("호스트가 치료를 확정하지 못했다")
	if not await _wait_until(func() -> bool:
			return not client_avatar.health.is_bleeding and not client_avatar.movement_locked \
				and not host_player.movement_locked, 5.0):
		return _fail("치료 결과(지혈·잠금 해제)가 복제되지 않았다")
	var count_at_heal: int = _blood_smell_count
	for i: int in range(120):
		await physics_frame
	if _blood_smell_count != count_at_heal:
		return _fail("치료 후에도 blood 냄새가 발신된다 (랩터 추적 근거가 남는다)")
	_log("치료 확정: 지혈 + 붕대 소비 + 냄새 정지 (붕대 잔여 %d)" % host_player.inventory.count_of(&"bandage"))

	# ── phase 6: 클라이언트가 재료 수집 → 모닥불 설치 의도 → 호스트 확정·복제 ──
	_log("--- phase 6: 재료 수집 + 모닥불 설치 (클라이언트 의도, 호스트 확정) ---")
	var base: Vector2 = host_view_client.global_position
	_spawn_item_both(host_main, client_main, "GoalStone", &"stone", 3, base + Vector2(24.0, 0.0))
	_spawn_item_both(host_main, client_main, "GoalWood", &"wood", 2, base + Vector2(-24.0, 24.0))
	_spawn_item_both(host_main, client_main, "SpareStone", &"stone", 2, base + Vector2(0.0, -24.0))
	await physics_frame
	for item_name: String in ["GoalStone", "GoalWood", "SpareStone"]:
		(client_main.get_node(item_name) as WorldItem).interact(client_avatar)
	if not await _wait_until(func() -> bool:
			return client_avatar.inventory.count_of(&"stone") == 5 \
				and client_avatar.inventory.count_of(&"wood") == 2, 5.0):
		return _fail("클라이언트 재료 획득이 확정·복제되지 않았다")
	_log("재료 확보: 돌 5 (여분 2 포함), 나무 2")

	if not await _walk_until(client_avatar, fire_position, 25.0):
		return _fail("클라이언트가 모닥불 자리에 도달하지 못했다")
	var client_site: CampfireSite = client_main.get_node("SurvivalDemo/CampfireSite")
	client_avatar.interactor.begin()
	if client_avatar.interactor.current_target != client_site:
		return _fail("클라이언트가 설치 자리를 잡지 못했다")
	client_avatar.interactor._process(client_site.config.build_seconds + 0.01)
	if not await _wait_until(func() -> bool:
			return host_site.campfire != null and host_site.campfire.is_lit \
				and client_site.campfire != null and client_site.campfire.is_lit, 5.0):
		return _fail("모닥불 설치가 호스트 확정·복제되지 않았다")
	if _campfire_lit_count != 1:
		return _fail("campfire_lit 이 %d회 발신됐다 — 호스트 단독 1회여야 한다 (랩터 중복 인식)" % _campfire_lit_count)
	if not await _wait_until(func() -> bool:
			return host_view_client.inventory.count_of(&"stone") == 2 \
				and client_avatar.inventory.count_of(&"stone") == 2, 5.0):
		return _fail("설치 재료가 정확히 한 번 소비되지 않았다")
	_log("모닥불 점화 확정: campfire_lit 1회 (호스트 단독), 재료 1회 소비, 여분 돌 2")

	# ── phase 7: ★ 함께 탈출 — 한 명만 보호되면 랩터는 물러나지 않는다 ──
	_log("--- phase 7: 랩터 결말 — 전원 보호 시에만 후퇴 ---")
	# 점화로 랩터가 일단 물러나 이탈 반경(radius*1.3) 밖으로 나간다.
	if not await _wait_until(func() -> bool:
			return host_raptor.state != Raptor.State.FLEE \
				and host_raptor.global_position.distance_to(fire_position) > fire_radius * 1.3, 30.0, _report_raptor):
		return _fail("점화 후 랩터가 이탈 반경 밖으로 물러나지 않았다")
	# 호스트가 불 반경 밖(랩터와 불 사이)에 남는다 — 노출된 동료 상황.
	var exposed_position: Vector2 = host_raptor.global_position \
		+ (fire_position - host_raptor.global_position).normalized() * 60.0
	if exposed_position.distance_to(fire_position) <= fire_radius:
		return _fail("검증 전제 붕괴: 노출 위치가 불 반경 안이다")
	host_player.global_position = exposed_position
	_log("호스트 노출 배치: %s (불에서 %.0fpx, 랩터에서 %.0fpx)" % [
		exposed_position.snapped(Vector2.ONE), exposed_position.distance_to(fire_position),
		exposed_position.distance_to(host_raptor.global_position)])
	# ★ 클라이언트만 보호된 상태 — 랩터는 물러나지 않고 노출된 호스트를 추격해야 한다.
	if not await _wait_until(func() -> bool:
			return host_raptor.state == Raptor.State.CHASE, 10.0, _report_raptor):
		return _fail("한 명만 보호된 상태에서 랩터가 노출된 동료를 추격하지 않았다")
	if host_raptor.move_target.distance_to(host_player.global_position) \
			> host_raptor.move_target.distance_to(client_avatar.global_position):
		return _fail("랩터가 보호된 플레이어를 추격한다 — 노출된 동료를 추격해야 한다")
	_log("★ 한 명만 보호 → 랩터가 노출된 호스트를 추격 (물러나지 않음) 확인")

	# 호스트도 불 반경 안으로 — 이제 전원 보호, 랩터가 비로소 물러난다.
	host_player.global_position = fire_position + Vector2(30.0, 0.0)
	if not await _wait_until(func() -> bool:
			return host_raptor.state == Raptor.State.FLEE, 10.0, _report_raptor):
		return _fail("두 명 다 불 반경 안인데 랩터가 물러나지 않았다")
	var flee_start: float = host_raptor.global_position.distance_to(fire_position)
	for i: int in range(180):
		await physics_frame
	var flee_end: float = host_raptor.global_position.distance_to(fire_position)
	if flee_end <= flee_start:
		return _fail("랩터가 불에서 멀어지지 않았다 (%.0f → %.0f)" % [flee_start, flee_end])
	if not await _wait_until(func() -> bool: return client_raptor.state == host_raptor.state, 5.0):
		return _fail("후퇴 상태가 클라이언트 랩터로 복제되지 않았다")
	_log("★ 전원 보호 → 랩터 후퇴 확인 (불과의 거리 %.0f → %.0f, 클라이언트 복제)" % [flee_start, flee_end])

	# ── phase 8 (에필로그): 재접속 — 인벤토리·상태 복원 + 총합 불변 + 의도 재동작 ──
	_log("--- phase 8: 재접속 재동기화 에필로그 ---")
	var stone_before: int = host_view_client.inventory.count_of(&"stone")
	client_session.leave_session()
	if not await _wait_until(func() -> bool: return host_session.get_players().size() == 1, 10.0):
		return _fail("이탈이 관측되지 않았다")
	if not host_session.has_reconnect_slot(client_id):
		return _fail("120초 재접속 슬롯이 열리지 않았다")
	if client_session.join_session({ address = "127.0.0.1", port = port, player_id = client_id }) != OK:
		return _fail("재참가가 시작되지 않았다")
	if not await _wait_until(func() -> bool:
			return host_session.get_players().size() == 2 and client_main.has_node(avatar_path), 10.0):
		return _fail("재접속 아바타가 스폰되지 않았다")
	var restored_avatar: Player = client_main.get_node(avatar_path)
	if not await _wait_until(func() -> bool:
			return restored_avatar.inventory.count_of(&"stone") == stone_before, 5.0):
		return _fail("재접속한 클라이언트가 인벤토리를 되찾지 못했다")
	if host_view_client.inventory.count_of(&"stone") != stone_before:
		return _fail("재접속으로 아이템이 복제·소실됐다 (%d != %d)" % [
			host_view_client.inventory.count_of(&"stone"), stone_before])
	if restored_avatar.health.is_bleeding:
		return _fail("치료된 상태가 복원되지 않았다 (출혈 재발)")
	_log("재접속 복원: 돌 %d 유지 (복제·소실 0), 출혈 없음" % stone_before)
	# 재접속한 피어의 의도가 다시 동작한다 (RpcGuard 재등록).
	_spawn_item_both(host_main, client_main, "EpilogueStone", &"stone", 1,
		host_view_client.global_position + Vector2(24.0, 0.0))
	await physics_frame
	(client_main.get_node("EpilogueStone") as WorldItem).interact(restored_avatar)
	if not await _wait_until(func() -> bool:
			return host_view_client.inventory.count_of(&"stone") == stone_before + 1, 5.0):
		return _fail("재접속한 피어의 줍기 의도가 동작하지 않았다")
	_log("재접속 후 의도 동작 확인: 줍기 확정 (돌 %d)" % (stone_before + 1))

	if _campfire_lit_count != 1:
		return _fail("최종 campfire_lit 발신 %d회 — 전 구간에서 호스트 단독 1회여야 한다" % _campfire_lit_count)
	_log("=== 2주 목표 장면 통합 하네스 성공: 방 생성 → 2인 탐색 → 부상 → 냄새 추적 → 치료 → 모닥불 탈출(전원 보호 시에만 후퇴) → 재접속 복원 ===")
	quit(0)


## 브랜치 루트 + 독립 MultiplayerAPI + main.tscn 인스턴스로 '기계' 하나를 만든다.
func _make_machine(machine_name: String) -> Node:
	var root: Node = Node.new()
	root.name = machine_name
	get_root().add_child(root)
	set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var main: Node2D = MainScene.instantiate()
	main.name = "Main"
	root.add_child(main)
	# 결정성 (B-01): 랩터 배회 RNG 를 고정 seed 로 덮어쓴다.
	var raptor: Raptor = main.get_node("Raptor")
	raptor.rng.seed = RAPTOR_RNG_SEED
	return root


## 같은 씬을 양쪽이 로드한 상황: 같은 상대 경로·수량의 아이템을 양쪽 기계에 만든다.
func _spawn_item_both(host_main: Node2D, client_main: Node2D, item_name: String,
		item_id: StringName, count: int, item_position: Vector2) -> void:
	for main: Node2D in [host_main, client_main]:
		var item: WorldItem = WorldItemScene.instantiate()
		item.name = item_name
		item.item_id = item_id
		item.count = count
		main.add_child(item)
		item.global_position = item_position


## 실제 입력 액션으로 mover 가 target 에 닿을 때까지 걷는다 (아이소 역변환).
## 같은 입력을 양쪽 기계의 로컬 아바타가 읽는다 — 두 명이 나란히 걷는다.
func _walk_until(mover: Player, target: Vector2, timeout_seconds: float) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	var elapsed: int = 0
	while mover.global_position.distance_to(target) > 24.0:
		if elapsed >= max_frames:
			_release_moves()
			return false
		var direction: Vector2 = target - mover.global_position
		var raw: Vector2 = Vector2(direction.x * 0.5 + direction.y, -direction.x * 0.5 + direction.y)
		_set_move(&"move_right", &"move_left", raw.x)
		_set_move(&"move_down", &"move_up", raw.y)
		await physics_frame
		elapsed += 1
	_release_moves()
	await physics_frame
	return true


func _set_move(positive: StringName, negative: StringName, amount: float) -> void:
	if amount > 8.0:
		Input.action_press(positive)
		Input.action_release(negative)
	elif amount < -8.0:
		Input.action_press(negative)
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


func _release_moves() -> void:
	for action: StringName in [&"move_right", &"move_left", &"move_up", &"move_down"]:
		Input.action_release(action)


func _report_raptor() -> void:
	var host_raptor: Raptor = get_root().get_node("HostMachine/Main/Raptor")
	_log("raptor=%s state=%s target=%s" % [
		host_raptor.global_position.snapped(Vector2.ONE), host_raptor.get_state_name(),
		host_raptor.move_target.snapped(Vector2.ONE)])


## condition 이 참이 될 때까지 대기. report 는 1초마다 호출한다.
func _wait_until(condition: Callable, timeout_seconds: float, report: Callable = Callable()) -> bool:
	var max_frames: int = int(timeout_seconds * 60.0)
	for frame_index: int in range(max_frames):
		if condition.call():
			return true
		if report.is_valid() and frame_index % 60 == 0:
			report.call()
		await physics_frame
	return condition.call()


func _log(message: String) -> void:
	print("[t=%5.1fs] %s" % [
		float(Engine.get_physics_frames() - _epoch_physics_frames) / 60.0, message])


func _fail(reason: String) -> void:
	_log("=== 2주 목표 장면 통합 하네스 실패: %s ===" % reason)
	quit(1)

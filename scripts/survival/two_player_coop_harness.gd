extends SceneTree

## 헤드리스 2인 협동 하네스 — W2-T2 (개발 빌드 전용, 게임 코드 아님).
## 실행: /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s scripts/survival/two_player_coop_harness.gd
##
## 한 프로세스에서 실제 main.tscn 2개(호스트 기계/클라이언트 기계)를 실제 루프백
## 소켓으로 연결해 2주 목표 장면의 협동 구간을 자동 판정한다:
##   2인 접속 → ★같은 아이템 동시 획득(정확히 1명, 복제 0, 소실 0)
##   → 클라이언트 원격 획득 복제 → 클라이언트 부상(변조 피해량 10000 → 호스트 클램프)
##   → 호스트 냄새 격자에 blood 축적 (발신은 호스트 1배 — 클라 중복 발신 시 2배로 잡힌다)
##   → 호스트가 붕대 치료 확정(원격 환자 이동 잠금 포함) → 냄새 발신 정지·격자 감쇠.
## 전 구간 자동 판정, 실패 시 종료 코드 1.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const NetTestRigScript = preload("res://tests/support/net_test_rig.gd")
const RAPTOR_RNG_SEED: int = 3
const SMELL_WINDOW_FRAMES: int = 180  # 3.0초 — 피 냄새 주기 0.5초면 6회 발신 예상.

var _frames: int = 0
var _blood_smell_count: int = 0
var _rig: RefCounted


func _init() -> void:
	_rig = NetTestRigScript.new(self)
	_run()


func _run() -> void:
	await process_frame

	# 0) 두 '기계' 구성 + W2-T2 노드가 실제 게임 씬에 배선됐는지 관문 검사.
	_log("--- phase 0: 호스트/클라이언트 기계에 main.tscn 로드 ---")
	var host_root: Node = _make_machine("HostMachine")
	var client_root: Node = _make_machine("ClientMachine")
	var host_main: Node2D = host_root.get_node("Main")
	var client_main: Node2D = client_root.get_node("Main")

	for required: String in ["NetSession", "NetMovement", "Players", "Player", "NetPickup", "NetSurvival", "SmellGrid"]:
		if host_main.get_node_or_null(required) == null:
			return _fail("main.tscn 에 %s 노드가 없다 — W2-T2 가 게임 씬에 연결되지 않았다" % required)
	var host_session: LocalSessionService = host_main.get_node("NetSession")
	var client_session: LocalSessionService = client_main.get_node("NetSession")
	var host_player: Player = host_main.get_node("Player")
	var host_grid: SmellGrid = host_main.get_node("SmellGrid")
	var client_survival: NetSurvival = client_main.get_node("NetSurvival")
	_log("main.tscn 2개 로드 완료. NetPickup/NetSurvival 배선 확인")

	get_root().get_node("EventBus").smell_emitted.connect(
		func(_position: Vector2, _strength: float, kind: StringName) -> void:
			if kind == &"blood":
				_blood_smell_count += 1)

	# 1) 접속.
	_log("--- phase 1: 호스트 개설 + 클라이언트 참가 ---")
	if _rig.start_host(host_session) != OK:
		return _fail("host_session 실패")
	if _rig.connect_client(client_session, host_session) != OK:
		return _fail("join_session 실패")
	if not await _wait_until(func() -> bool:
			return host_session.get_players().size() == 2, 10.0):
		return _fail("호스트가 참가를 관측하지 못했다")
	var client_id: StringName = client_session.get_local_player_id()
	var avatar_path: NodePath = NodePath("Players/%s" % client_id)
	if not await _wait_until(func() -> bool:
			return host_main.has_node(avatar_path) and client_main.has_node(avatar_path), 10.0):
		return _fail("클라이언트 아바타가 양쪽에 스폰되지 않았다")
	var host_view_client: Player = host_main.get_node(avatar_path)
	var client_avatar: Player = client_main.get_node(avatar_path)
	_log("접속 완료. client_id=%s 아바타 위치 %s" % [client_id, host_view_client.global_position.snapped(Vector2.ONE)])

	# 2) ★ 같은 아이템 동시 획득 — 협동 게임의 고전 복제/소실 버그 관문.
	_log("--- phase 2: 같은 프레임 동시 획득 경합 ---")
	var contested_position: Vector2 = (host_player.global_position + host_view_client.global_position) * 0.5
	_spawn_item(host_main, "ContestedStone", &"stone", 3, contested_position)
	_spawn_item(client_main, "ContestedStone", &"stone", 3, contested_position)
	await physics_frame
	_frames += 1

	# 같은 프레임: 호스트도 줍고 클라이언트도 줍는다.
	(host_main.get_node("ContestedStone") as WorldItem).interact(host_player)
	(client_main.get_node("ContestedStone") as WorldItem).interact(client_avatar)
	if not await _wait_until(func() -> bool:
			return host_main.get_node_or_null("ContestedStone") == null \
				and client_main.get_node_or_null("ContestedStone") == null, 5.0):
		return _fail("경합 아이템이 양쪽 월드에서 사라지지 않았다")
	for i: int in range(30):
		await physics_frame
		_frames += 1
	var host_stone: int = host_player.inventory.count_of(&"stone")
	var client_stone_on_host: int = host_view_client.inventory.count_of(&"stone")
	_log("경합 결과: 호스트 %d개 / 클라이언트(호스트 권위) %d개" % [host_stone, client_stone_on_host])
	if host_stone + client_stone_on_host != 3:
		return _fail("총합이 보존되지 않았다 (%d+%d != 3) — 복제 또는 소실" % [host_stone, client_stone_on_host])
	if host_stone != 0 and client_stone_on_host != 0:
		return _fail("두 명이 같은 아이템을 나눠 가졌다 — 정확히 1명만 획득해야 한다")
	if client_avatar.inventory.count_of(&"stone") != client_stone_on_host:
		return _fail("클라이언트 인벤토리 복제본이 호스트 확정과 다르다")

	# 2b) 클라이언트 단독 획득 — 원격 줍기 확정·복제 전 구간.
	_log("--- phase 2b: 클라이언트 원격 획득 복제 ---")
	_spawn_item(host_main, "ClientStone", &"stone", 2, client_avatar.global_position + Vector2(24.0, 0.0))
	_spawn_item(client_main, "ClientStone", &"stone", 2, client_avatar.global_position + Vector2(24.0, 0.0))
	await physics_frame
	_frames += 1
	(client_main.get_node("ClientStone") as WorldItem).interact(client_avatar)
	if not await _wait_until(func() -> bool:
			return host_view_client.inventory.count_of(&"stone") == client_stone_on_host + 2 \
				and client_avatar.inventory.count_of(&"stone") == client_stone_on_host + 2 \
				and host_main.get_node_or_null("ClientStone") == null \
				and client_main.get_node_or_null("ClientStone") == null, 5.0):
		return _fail("클라이언트 원격 획득이 확정·복제되지 않았다")
	_log("원격 획득 복제 완료 (돌 +2)")

	# 3) 클라이언트 부상 — 변조된 피해량 주장(10000)을 호스트가 클램프한다 (설계서 7.4).
	_log("--- phase 3: 클라이언트 부상 (변조 피해량 10000 주장) ---")
	client_survival.request_hurt_for(client_avatar, 10000.0)
	if not await _wait_until(func() -> bool:
			return host_view_client.health.is_bleeding, 5.0):
		return _fail("호스트가 부상 의도를 확정하지 않았다")
	var max_damage: float = host_view_client.health.config.remote_hurt_max_damage
	var health_after: float = host_view_client.health.current_health
	if not host_view_client.health.is_alive() or health_after < host_view_client.health.config.max_health - max_damage - 3.0:
		return _fail("변조 피해량이 그대로 적용됐다 (health=%.0f)" % health_after)
	_log("부상 확정: health=%.1f (클램프 %.0f 적용), bleeding=%s" % [
		health_after, max_damage, host_view_client.health.is_bleeding])

	# 3b) 호스트 냄새 격자에 blood 가 1배 속도로 쌓인다 (클라 중복 발신이면 2배로 잡힌다).
	_log("--- phase 3b: 피 냄새 축적 %d프레임 관측 ---" % SMELL_WINDOW_FRAMES)
	var count_before: int = _blood_smell_count
	for i: int in range(SMELL_WINDOW_FRAMES):
		await physics_frame
		_frames += 1
	var emissions: int = _blood_smell_count - count_before
	var expected: int = int(float(SMELL_WINDOW_FRAMES) / 60.0 / host_view_client.health.config.bleed_smell_interval)
	_log("blood 발신 %d회 (기대 %d회, 호스트 단독 발신 기준)" % [emissions, expected])
	if emissions < expected - 2 or emissions > expected + 2:
		return _fail("blood 발신 횟수가 호스트 1배가 아니다 (%d회) — 중복 발신 또는 발신 누락" % emissions)
	var smell_at_patient: float = host_grid.get_smell_at(host_view_client.global_position)
	if smell_at_patient <= 0.0:
		return _fail("호스트 냄새 격자에 blood 가 쌓이지 않았다")
	if not client_avatar.health.is_bleeding:
		return _fail("출혈 상태가 클라이언트로 복제되지 않았다")
	_log("호스트 격자 환자 위치 농도 %.1f, 클라 복제본 bleeding=%s" % [
		smell_at_patient, client_avatar.health.is_bleeding])

	# 4) 호스트가 붕대로 치료 — 길게 누르기, 양쪽 이동 잠금, 호스트 검증·확정 (설계서 5.2).
	_log("--- phase 4: 호스트 붕대 치료 (길게 누르기) ---")
	host_player.inventory.add_item(&"bandage", 1)
	host_player.global_position = host_view_client.global_position + Vector2(-40.0, 0.0)
	await physics_frame
	await physics_frame
	_frames += 2
	host_player.interactor.begin()
	if host_player.interactor.current_target == null:
		return _fail("호스트가 출혈 중인 동료의 HealTarget 을 잡지 못했다")
	# 홀드 중반: 원격 환자(클라이언트 기계의 로컬 아바타)도 이동이 잠겨야 한다.
	if not await _wait_until(func() -> bool:
			return client_avatar.movement_locked, 3.0):
		return _fail("치료 중 원격 환자의 이동이 잠기지 않았다")
	if not host_player.movement_locked:
		return _fail("치료 중 치료자의 이동이 잠기지 않았다")
	_log("치료 홀드 중 양쪽 이동 잠금 확인")
	if not await _wait_until(func() -> bool:
			return not host_view_client.health.is_bleeding, 8.0):
		return _fail("호스트가 치료를 확정하지 못했다 (출혈 지속)")
	if host_player.inventory.count_of(&"bandage") != 0:
		return _fail("붕대가 소비되지 않았다")
	if not await _wait_until(func() -> bool:
			return not client_avatar.health.is_bleeding \
				and not client_avatar.movement_locked and not host_player.movement_locked, 5.0):
		return _fail("치료 결과(지혈·잠금 해제)가 클라이언트로 복제되지 않았다")
	_log("치료 확정 복제 완료: 지혈 + 붕대 소비 + 잠금 해제")

	# 4b) 냄새 정지 — 발신이 멈추고 격자가 감쇠한다 (랩터 추적 근거 소멸).
	_log("--- phase 4b: 냄새 정지 관측 ---")
	var count_at_heal: int = _blood_smell_count
	var smell_at_heal: float = host_grid.get_smell_at(host_view_client.global_position)
	for i: int in range(120):
		await physics_frame
		_frames += 1
	if _blood_smell_count != count_at_heal:
		return _fail("치료 후에도 blood 냄새가 발신된다 (%d회 추가)" % (_blood_smell_count - count_at_heal))
	if not await _wait_until(func() -> bool:
			return host_grid.get_smell_at(host_view_client.global_position) < maxf(smell_at_heal * 0.5, 1.0), 10.0):
		return _fail("치료 후 냄새 격자가 감쇠하지 않는다")
	_log("냄새 정지 확인: 발신 0회, 격자 %.1f → %.1f" % [
		smell_at_heal, host_grid.get_smell_at(host_view_client.global_position)])

	# 5) 정리.
	_log("--- phase 5: 세션 정리 ---")
	client_session.leave_session()
	if not await _wait_until(func() -> bool:
			return host_session.get_players().size() == 1, 10.0):
		return _fail("이탈이 정리되지 않았다")

	_log("=== 2인 협동 하네스 성공: 동시 획득 1명 확정·복제/소실 0·피해 클램프·호스트 단독 냄새·붕대 치료 확정·냄새 정지 ===")
	_rig.disconnect_all()
	if not _rig.assert_no_leaked_peers():
		return _fail("NetTestRig peer 누수")
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
	# 랩터 배회 RNG 고정 — 판정과 무관하지만 로그 재현성을 위해 (B-01 관례).
	var raptor: Raptor = main.get_node("Raptor")
	raptor.rng.seed = RAPTOR_RNG_SEED
	return root


## 같은 씬을 양쪽이 로드한 상황을 재현: 같은 상대 경로·수량의 아이템을 만든다.
func _spawn_item(main: Node2D, item_name: String, item_id: StringName, count: int, item_position: Vector2) -> void:
	var item: WorldItem = (load("res://scenes/items/world_item.tscn") as PackedScene).instantiate()
	item.name = item_name
	item.item_id = item_id
	item.count = count
	main.add_child(item)
	item.global_position = item_position


func _wait_until(condition: Callable, timeout_seconds: float) -> bool:
	return await _rig.pump_until(condition, timeout_seconds)


func _log(message: String) -> void:
	print("[t=%5.1fs] %s" % [float(_frames) / 60.0, message])


func _fail(reason: String) -> void:
	_log("=== 2인 협동 하네스 실패: %s ===" % reason)
	_rig.disconnect_all()
	quit(1)

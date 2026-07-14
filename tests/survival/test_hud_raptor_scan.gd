extends GutTest

## HUD 랩터 연결 스캔 성능 픽스 (W3-4 픽스2, 경미).
## ★ 버그: 랩터가 없거나 늦게 생기는 화면에서 _ensure_raptors_connected 가 매 프레임
##   get_tree().root 전체를 재귀 스캔했다(성능문서 6.1: 전체 노드 트리 검색 금지).
## 고침: 못 찾았을 때는 RAPTOR_SCAN_INTERVAL_SECONDS 주기로만 재시도한다.

const HudScene: PackedScene = preload("res://scenes/ui/hud/hud.tscn")

func _make_hud() -> Hud:
	var world: Node2D = add_child_autofree(Node2D.new())
	var hud: Hud = HudScene.instantiate()
	world.add_child(hud)
	return hud

## 랩터가 전혀 없는 화면: 첫 호출은 즉시 1회 시도하지만(성공 시나리오를 놓치지 않도록),
## 그 뒤로는 주기가 찰 때까지 다시 스캔하지 않아야 한다.
func test_raptor_scan_retries_on_an_interval_not_every_frame_when_none_exist() -> void:
	var hud: Hud = _make_hud()

	hud._ensure_raptors_connected(1.0 / 60.0)
	assert_false(hud._raptors_connected, "전제: 랩터가 없으니 연결되지 않아야 한다")
	assert_eq(hud._raptor_scan_elapsed, 0.0,
		"첫 호출은 즉시 스캔을 시도해야 한다 (이미 만료된 값으로 시작)")

	# 매 프레임 호출해도(1/60초씩 30회 = 0.5초 누적) 재시도 주기(2.0초) 전이면
	# 다시 스캔하면 안 된다 — 스캔했다면 _raptor_scan_elapsed 가 다시 0으로 리셋됐을 것이다.
	for i: int in range(30):
		hud._ensure_raptors_connected(1.0 / 60.0)
	assert_almost_eq(hud._raptor_scan_elapsed, 0.5, 0.01,
		"주기가 차기 전에는 재시도(리셋)하지 않고 계속 누적만 해야 한다")

	# 남은 시간을 채우면 그제서야 다시 시도하고(여전히 랩터 없음) 리셋된다.
	hud._ensure_raptors_connected(hud.RAPTOR_SCAN_INTERVAL_SECONDS)
	assert_eq(hud._raptor_scan_elapsed, 0.0, "주기가 차면 재시도하고 다시 리셋되어야 한다")


## 회귀 방지: 스캔 자체는 여전히 동작해 실제로 있는 랩터를 찾아 연결한다.
func test_raptor_scan_still_connects_when_a_raptor_exists() -> void:
	var hud: Hud = _make_hud()
	add_child_autofree(Raptor.new())

	hud._ensure_raptors_connected(1.0 / 60.0)

	assert_true(hud._raptors_connected, "랩터가 있으면 첫 시도에서 바로 연결되어야 한다")

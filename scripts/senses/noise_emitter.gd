class_name NoiseEmitter
extends RefCounted

## EventBus.noise_emitted 발신 API.
## 같은 행동/위치의 반복 소리는 짧은 창에서 병합한다.

var _last_by_profile: Dictionary = {}

## now_seconds 를 생략하면 엔진 시계를 쓴다. 테스트만 결정성을 위해 주입한다.
func emit_profile(event_bus: Node, profile: NoiseProfile, position: Vector2, source: Node,
		now_seconds: float = -1.0, authority_only: bool = true) -> bool:
	if event_bus == null or profile == null or profile.radius <= 0.0 or not position.is_finite():
		return false
	if authority_only:
		if source == null or not source.is_multiplayer_authority():
			return false
	if now_seconds < 0.0:
		now_seconds = float(Time.get_ticks_msec()) / 1000.0
	# 프로필당 마지막 발신 기록은 제자리에서 고쳐 쓴다 — 발신마다 새 Dictionary 금지 (성능문서 6.1).
	var last: Dictionary = _last_by_profile.get(profile.id, {})
	if last.is_empty():
		_last_by_profile[profile.id] = { position = position, time = now_seconds }
	else:
		var elapsed: float = now_seconds - float(last.time)
		if elapsed >= 0.0 and elapsed < profile.merge_window_seconds \
				and position.distance_to(last.position) <= profile.merge_distance_px:
			return false
		last.position = position
		last.time = now_seconds
	var perf: Node = _perf_monitor()
	if perf != null:
		perf.begin_sample(&"noise")
	event_bus.noise_emitted.emit(position, profile.radius, source)
	if perf != null:
		perf.end_sample(&"noise")
	return true


func _perf_monitor() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("PerfMonitor")

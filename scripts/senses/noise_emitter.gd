class_name NoiseEmitter
extends RefCounted

## EventBus.noise_emitted 발신 API.
## 같은 행동/위치의 반복 소리는 짧은 창에서 병합한다.

var _last_by_profile: Dictionary = {}

func emit_profile(event_bus: Node, profile: NoiseProfile, position: Vector2, source: Node,
		now_seconds: float, authority_only: bool = true) -> bool:
	if event_bus == null or profile == null or profile.radius <= 0.0 or not position.is_finite():
		return false
	if authority_only:
		if source == null or not source.is_multiplayer_authority():
			return false
	if _should_merge(profile, position, now_seconds):
		return false
	_last_by_profile[profile.id] = { position = position, time = now_seconds }
	event_bus.noise_emitted.emit(position, profile.radius, source)
	return true

func _should_merge(profile: NoiseProfile, position: Vector2, now_seconds: float) -> bool:
	var last: Dictionary = _last_by_profile.get(profile.id, {})
	if last.is_empty():
		return false
	var elapsed: float = now_seconds - float(last.time)
	if elapsed < 0.0 or elapsed >= profile.merge_window_seconds:
		return false
	return position.distance_to(last.position) <= profile.merge_distance_px

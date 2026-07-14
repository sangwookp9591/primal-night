class_name SenseIndicatorModel
extends RefCounted

## 최소 감각 피드백 모델 (설계서 5.4 바람 전달 / 12장 접근성 — 음소거 사용자도 위험 인지).
## 렌더와 분리된 순수 상태다. HUD 는 이 값만 읽어 그린다 (렌더 픽셀 검증은 하지 않는다).

const SOUND_INDICATOR_SECONDS: float = 4.0

var wind_direction: Vector2 = Vector2.ZERO
var wind_strength: float = 0.0
var raptor_alert: bool = false

var _sound_direction: Vector2 = Vector2.ZERO
var _sound_remaining: float = 0.0

func set_wind(direction: Vector2, strength: float) -> void:
	wind_direction = direction
	wind_strength = strength

func has_wind() -> bool:
	return wind_strength > 0.0 and not wind_direction.is_zero_approx()

## 청취자 기준 방향만 남긴다 — 발신 위치 자체는 저장하지 않는다 (공정성 규칙, 설계서 5.3).
func report_noise(source_position: Vector2, listener_position: Vector2) -> void:
	var offset: Vector2 = source_position - listener_position
	if offset.is_zero_approx():
		return
	_sound_direction = offset.normalized()
	_sound_remaining = SOUND_INDICATOR_SECONDS

func has_recent_sound() -> bool:
	return _sound_remaining > 0.0

func sound_direction() -> Vector2:
	return _sound_direction if has_recent_sound() else Vector2.ZERO

## 시간 경과 처리. HUD 가 _process(delta) 에서 호출한다.
func update(delta: float) -> void:
	if _sound_remaining > 0.0:
		_sound_remaining = maxf(_sound_remaining - delta, 0.0)

func set_raptor_chasing(is_chasing: bool) -> void:
	raptor_alert = is_chasing

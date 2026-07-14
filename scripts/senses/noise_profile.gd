class_name NoiseProfile
extends Resource

## 행동별 소리 데이터 (설계서 5.3).
## 소리는 노드가 아니라 이벤트로 발신된다.

@export var id: StringName = &""
@export var radius: float = 0.0
@export var merge_window_seconds: float = 0.25
@export var merge_distance_px: float = 16.0

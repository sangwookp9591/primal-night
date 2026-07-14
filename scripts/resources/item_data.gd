class_name ItemData
extends Resource

## 아이템 정의. UI 표시값도 반드시 이 리소스에서 생성한다 (설계서 5.6/15장).
## GameData 가 data/items/*.tres 를 id 로 캐시한다.

@export var id: StringName
@export var display_name: String = ""
@export var stackable: bool = false
## 한 슬롯에 쌓을 수 있는 최대 수량.
@export var max_stack: int = 1
@export var weight: float = 0.0
@export var emits_smell: bool = false
@export var smell_strength: float = 0.0
@export var smell_interval_seconds: float = 0.5
@export var smell_kind: StringName = &""

## 스택 상한. stackable 과 max_stack 이 어긋나도 인벤토리는 이 값 하나만 믿는다.
func get_stack_limit() -> int:
	if not stackable:
		return 1
	return maxi(max_stack, 1)

func is_smell_source() -> bool:
	return emits_smell and smell_strength > 0.0 and smell_interval_seconds > 0.0

func get_smell_kind() -> StringName:
	return smell_kind if smell_kind != &"" else id

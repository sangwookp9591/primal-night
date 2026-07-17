class_name CarcassProfile
extends Resource

## 사체 종별 해체 데이터 (정본 §14.4).
##
## 해체 시간·산출·냄새를 전부 데이터로 둔다. 도구 배수를 여기 두는 이유는
## `ItemData` 에 해체 필드를 더하면 모든 아이템이 해체를 알게 되기 때문이다 —
## 해체를 아는 쪽은 사체다.

@export var id: StringName = &""
@export var display_name: String = ""

## 구간 수. 정본 §14.4 의 25/50/75/100% 규칙이라 4 다.
@export var stage_count: int = 4

## 구간 1개당 해체 시간 (돌칼 기준). 정본 §14.4 "돌칼 8초".
## 4구간 × 8초 = 32초로 "완전 해체 = 20~40초 노출" 안에 들어간다.
@export var base_butcher_seconds: float = 8.0

## 도구별 시간 배수. **여기 없는 도구로는 해체할 수 없다** — 맨손 불가가
## 별도 분기가 아니라 이 표의 부재로 표현된다 (정본 §14.4 "맨손 불가").
## 뼈 긁개 0.75 = 정본 §14.2 "사체 해체 시간 25% 감소".
@export var tool_time_multipliers: Dictionary = {
	&"stone_knife": 1.0,
	&"bone_scraper": 0.75,
}

## 구간 순서대로의 산출 {item_id: count}. 정본 §14.4 "25%마다 미개봉 슬롯 1개".
@export var stage_yields: Array[Dictionary] = []

## 피 냄새 강도 (정본 §14.4: 신선 80 / 일부 해체 55 / 골격 0).
## 골격 0 은 값이 아니라 원천 해제로 표현한다.
@export var fresh_smell_strength: float = 80.0
@export var partial_smell_strength: float = 55.0
@export var smell_interval_seconds: float = 0.5
@export var smell_kind: StringName = &"carcass"

func is_valid() -> bool:
	return id != &"" and stage_count > 0 and base_butcher_seconds > 0.0 \
		and not tool_time_multipliers.is_empty()

## 해체 시간 배수. 도구가 아니면 INF — 호출부가 "해체 불가"로 읽는다.
func time_multiplier_for(tool_id: StringName) -> float:
	return float(tool_time_multipliers.get(tool_id, INF))

## 구간 산출. 정의가 없는 구간은 빈 Dictionary (산출 없음).
func yields_for_stage(stage: int) -> Dictionary:
	if stage < 0 or stage >= stage_yields.size():
		return {}
	return stage_yields[stage]

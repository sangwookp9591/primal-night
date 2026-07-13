class_name SmellGridConfig
extends Resource

## 냄새 격자 규칙 수치 (설계서 9.2: 규칙 수치는 데이터 리소스로).
## 갱신 빈도는 성능문서 5.2 기본값(초당 4회)을 따른다.

## 냄새 셀 한 변(px). 타일(64x32)보다 커야 한다 — 저해상도 격자 (성능문서 5.2).
@export var cell_size: float = 128.0

## 격자 갱신 주기(초). 0.25 = 초당 4회 (성능문서 5.2).
@export var tick_interval: float = 0.25

## 틱마다 셀에 남는 비율 (시간 감쇠).
@export var decay_factor: float = 0.8

## 틱마다 바람 방향 이웃 셀로 이동하는 비율 (바람 세기 1.0 기준).
@export var advect_fraction: float = 0.4

## 이 값 미만이면 셀을 비활성화한다 (활성 셀만 갱신, 성능문서 5.2).
@export var min_active_value: float = 0.5

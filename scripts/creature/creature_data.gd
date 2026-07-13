class_name CreatureData
extends Resource

## 공룡 행동 수치 (설계서 9.2: 하드코딩 금지, 데이터 리소스로 정의).

@export var walk_speed: float = 90.0
@export var chase_speed: float = 200.0

## 이 거리 안에서 플레이어를 실제로 지각하면 추격에 들어간다.
@export var sight_radius: float = 180.0
## 추격 중 이 거리보다 멀어지면 대상을 잃는다 (진입/이탈 히스테리시스).
@export var lose_sight_radius: float = 280.0

## 자기 위치의 냄새 농도가 이 값 이상이면 경사를 따라 조사한다.
@export var smell_threshold: float = 8.0

## 조사 목표에 이만큼 접근하면 도착으로 판정한다.
@export var investigate_arrive_distance: float = 24.0

## 지각·상태 결정 주기(초). 매 프레임 재계산 금지 (성능문서 6.3).
@export var ai_tick_interval: float = 0.2

## 벽에 가로막힌 소리의 유효 반경 배율 (설계서 5.3: 지형과 벽은 소리를 감쇠한다).
@export var occlusion_attenuation: float = 0.5

## 불 회피 히스테리시스: 도주 해제는 불 반경 * 이 배율 밖에서만 (경계 진동 방지).
@export var fire_exit_ratio: float = 1.3

## 배회 목표를 고르는 반경.
@export var wander_range: float = 320.0

## 추격 전환 경고 신호 표시 시간(초) (설계서 3.2: 예고 없는 위협 금지).
@export var alert_seconds: float = 1.0

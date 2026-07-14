class_name CampfireConfig
extends Resource

## 모닥불 수치. 노드에 흩뿌리지 않는다.
## light_radius 는 T4 의 랩터가 회피 판단에 쓴다 (목표 장면: 모닥불까지 도망가면 물러난다).

@export var light_radius: float = 220.0
## 연료가 다 타면 꺼진다. 지금은 단순 타이머로 충분하다.
@export var fuel_seconds: float = 60.0

@export_group("Build cost")
@export var stone_cost: int = 3
@export var wood_cost: int = 2
## 설치에 걸리는 시간 (길게 누르기).
@export var build_seconds: float = 1.0

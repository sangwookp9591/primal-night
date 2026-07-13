class_name SurvivalConfig
extends Resource

## 프로토타입 생존 수치. 노드에 흩뿌리지 않고 여기서만 정의한다 (설계서 9.2).
## HUD 표시값도 이 리소스에서 생성한다 (설계서 5.6/15장).

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Stamina")
@export var max_stamina: float = 100.0
## 달리는 동안 초당 소모량.
@export var stamina_run_drain: float = 20.0
## 정지 중 초당 회복량.
@export var stamina_regen_idle: float = 15.0
## 걷는 중 초당 회복량.
@export var stamina_regen_walk: float = 7.0

@export_group("Bleeding")
## 출혈 중 초당 피해.
@export var bleed_damage_per_second: float = 2.0
## 피 냄새 발신 주기(초). 매 프레임 발신 금지 (성능문서 6.1).
@export var bleed_smell_interval: float = 0.5
@export var bleed_smell_strength: float = 60.0

@export_group("Healing")
## 동료가 상호작용을 길게 눌러 지혈하는 데 걸리는 시간 (설계서 5.2).
@export var bandage_hold_seconds: float = 2.0

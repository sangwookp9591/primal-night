class_name SurvivalConfig
extends Resource

## 프로토타입 생존 수치. 노드에 흩뿌리지 않고 여기서만 정의한다 (설계서 9.2).
## HUD 표시값도 이 리소스에서 생성한다 (설계서 5.6/15장).

@export_group("Health")
@export var max_health: float = 100.0
## HUD 단계 표시 경계 (설계서 10.1: 숫자 나열보다 단계 표시).
## 이 비율 아래면 "부상".
@export var health_hurt_ratio: float = 0.6
## 이 비율 아래면 "위독".
@export var health_critical_ratio: float = 0.3

@export_group("Stamina")
@export var max_stamina: float = 100.0
## 달리는 동안 초당 소모량.
@export var stamina_run_drain: float = 20.0
## 정지 중 초당 회복량.
@export var stamina_regen_idle: float = 15.0
## 걷는 중 초당 회복량.
@export var stamina_regen_walk: float = 7.0
## 소진 후 다시 달릴 수 있게 되는 회복 임계치.
## 0 보다 크기만 하면 달릴 수 있게 하면 매 프레임 달리기/걷기가 깜빡인다.
@export var stamina_recover_threshold: float = 20.0

@export_group("Bleeding")
## 출혈 중 초당 피해.
@export var bleed_damage_per_second: float = 2.0
## 피 냄새 발신 주기(초). 매 프레임 발신 금지 (성능문서 6.1).
@export var bleed_smell_interval: float = 0.5
@export var bleed_smell_strength: float = 60.0

@export_group("Healing")
## 동료가 상호작용을 길게 눌러 지혈하는 데 걸리는 시간 (설계서 5.2).
@export var bandage_hold_seconds: float = 2.0

@export_group("Network")
## 클라이언트 부상 의도가 주장할 수 있는 피해 상한 (설계서 7.4: 피해량 불신).
## 호스트는 주장값을 이 값으로 잘라서만 적용한다.
@export var remote_hurt_max_damage: float = 25.0

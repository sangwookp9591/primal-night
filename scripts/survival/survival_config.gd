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

@export_group("Survival Stats")
## 생존 수치 4종 (설계서 5.1). 10~15분 한 판에서 눈에 띄게 움직이되 바닥나지는 않는
## 회색 상자 값이다 — 실제 밸런스는 플레이 하네스(W4-T4) 이후에 조정한다.
## 초당 감소량 0.06 이면 12분(720초) 뒤 100 → 57 이다.
@export var water_drain_per_second: float = 0.06
@export var food_drain_per_second: float = 0.05
@export var temperature_drain_per_second: float = 0.04
## 모닥불 반경 안에서 초당 회복량 — 떨어지는 속도보다 훨씬 빨라야 불이 의미가 있다.
@export var temperature_regen_near_fire: float = 3.0
## 움직이는 동안 초당 피로.
@export var fatigue_gain_per_second: float = 0.03
## 이동 거리(px)당 피로. 입력이 아니라 실제 이동량을 본다 — 달리면 그만큼 더 지친다.
## 호스트는 남의 입력을 모르지만 남의 좌표는 알기 때문에, 원격 아바타에도 그대로 적용된다.
@export var fatigue_gain_per_pixel: float = 0.002
## 제자리에서 쉴 때 초당 회복량. 쉬는 것이 곧 회복이다.
@export var fatigue_recover_per_second: float = 0.5

## HUD 단계 경계 (설계서 10.1). wellness(0..1) 가 이 아래면 주의 / 위험.
@export var stat_warn_ratio: float = 0.5
@export var stat_danger_ratio: float = 0.25

## 피로의 행동 연결 (계획서 W4-T3: 3~4주차에는 피로·체온만 약하게 붙인다).
## 탈진(피로 100%) 시 달리기 소모가 이 배율만큼 늘어난다 — 1.0 이면 2배.
@export var fatigue_run_drain_bonus: float = 0.6
## 탈진 시 스태미나 회복이 이 비율만큼 깎인다 — 0.6 이면 40% 속도.
@export var fatigue_regen_penalty: float = 0.6
## 수분 0일 때 스태미나 회복 감소 비율.
@export_range(0.0, 1.0) var water_stamina_regen_penalty: float = 0.6
## 피로+탈수 회복 페널티 합산 상한. 바닥에서도 회복이 완전히 멎지 않게 한다.
@export_range(0.0, 1.0) var stamina_regen_combined_penalty_cap: float = 0.9
## 출혈 중이 아닐 때의 자연 체력 회복과 포만 0에서의 감소 비율.
@export var natural_health_regen_per_second: float = 0.2
@export_range(0.0, 1.0) var food_health_regen_penalty: float = 1.0

@export_group("Bleeding")
## 출혈 중 초당 피해.
@export var bleed_damage_per_second: float = 2.0
## 피 냄새 발신 주기(초). 매 프레임 발신 금지 (성능문서 6.1).
@export var bleed_smell_interval: float = 0.5
@export var bleed_smell_strength: float = 60.0

@export_group("Injury")
## 다리 열상 중 이동 효율. PlayerConfig 공유 Resource 자체는 변경하지 않는다.
@export_range(0.0, 1.0, 0.05) var leg_laceration_move_multiplier: float = 0.7

@export_group("Healing")
## 동료가 상호작용을 길게 눌러 지혈하는 데 걸리는 시간 (설계서 5.2).
@export var bandage_hold_seconds: float = 2.0

@export_group("Network")
## 클라이언트 부상 의도가 주장할 수 있는 피해 상한 (설계서 7.4: 피해량 불신).
## 호스트는 주장값을 이 값으로 잘라서만 적용한다.
@export var remote_hurt_max_damage: float = 25.0

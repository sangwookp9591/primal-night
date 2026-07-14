# W2-T2 검증 리포트 — 아이템 획득 동시성 + 출혈·치료 2인 동기화

2026-07-14. W2-T1 네트워크 기반(SessionService / RpcGuard / MovementAuthority / NetMovement 패턴) 위에
아이템 획득과 피해·출혈·붕대 치료의 호스트 권위 동기화를 얹었다. 게임 코드에 ENet 노출 없음
(`grep -rn "ENet" scripts/items scripts/survival` → 0건). 전 과정 TDD (RED → GREEN → 원자적 커밋).

## 1. 구현 (계약 준수)

| 모듈 | 역할 | 패턴 |
|---|---|---|
| `scripts/items/net_pickup.gd` | 줍기 의도(아이템 경로만) → 호스트가 존재·수량·거리 검증 후 직렬 확정 → 신뢰 전송 복제 | NetMovement 의 `@rpc("any_peer")` 의도 / `@rpc("authority")` 확정 + RpcGuard 규칙 등록 |
| `scripts/survival/net_survival.gd` | 부상 의도(주장 피해량을 `remote_hurt_max_damage` 로 클램프), 체력·출혈 10Hz 스냅샷, 붕대 치료 세션(홀드 시간·붕대·거리·생존 호스트 검증, 양쪽 이동 잠금 복제) | 동일 |
| `scripts/survival/health_component.gd` | 출혈 시뮬(지속 피해 + `smell_emitted(&"blood")`)을 권위에서만 실행, `apply_replicated()` 복제 적용 | 설계서 7.2 냄새 호스트 권한 |
| `scripts/items/world_item.gd`, `heal_target.gd`, `debug_hurt.gd` | 넷 스택 존재 시 권위 경로로 라우팅, 없으면 로컬 폴백 (기존 GUT 무손상) | 덕 타이핑 유지 |
| `scenes/main.tscn` | NetPickup / NetSurvival 배선 (코디네이터 승인) | — |
| `.github/workflows/ci.yml` | 협동 하네스 관문 추가 (코디네이터 승인) | — |

아이템 id·수량·피해량은 클라이언트 페이로드에 없거나(줍기) 클램프된다(부상) — 설계서 7.4.
검증 거리(128px)·홀드 슬랙(0.25s)은 변조 방지 프로토콜 상수로 NetMovement 관례를 따랐다.

발견 사항: 헤드리스 하네스에서 두 기계(멀티플레이 브랜치)가 **하나의 물리 공간을 공유**해
Interactor 가 상대 기계의 HealTarget 을 직접 집는 경계 누수가 있었다 (RED 단계에서 검출).
`interactor.gd` 의 대상 탐색에 같은-브랜치(`area.multiplayer == multiplayer`) 필터를 추가해 차단했다.
프로덕션(기계 1개)에서는 항상 참인 조건이라 동작 변화가 없다.

## 2. TDD RED → GREEN 근거 (실제 출력)

### 아이템 동시 획득 (tests/inventory/test_net_pickup.gd, 6 tests)
RED (스켈레톤 — 확정·복제 없음):
```
[Failed]: [0] expected to equal [3]:  총합 보존: 복제도 소실도 없어야 한다
[Failed]: [0] expected to equal [3]:  첫 요청자만 획득한다
[Failed]: 아이템은 정확히 한 번 사라진다
[Failed]: 호스트가 남은 2자리만 채워야 한다   … 4/6 tests failing
```
GREEN: `All tests passed!` (같은 프레임 경합 → 정확히 1명, 월드 1회 소멸, 총합 보존, 복제본 일치).

### 피해 클램프·냄새 게이트·복제 (tests/survival/test_net_survival.gd, 9 tests)
RED (게이트·클램프·복제 부재):
```
[Failed]: 호스트가 부상 의도를 확정하고 출혈을 시작해야 한다
[Failed]: [100.0] expected to be <= than [75.0]:  호스트 규칙만큼은 피해를 입어야 한다
[Failed]: Expected the signal [smell_emitted] emit count of [2] to equal [1]:
          클라이언트 기계는 발신하지 않는다 — 발신하면 냄새가 2배로 쌓인다
[Failed]: 클라이언트 복제본이 호스트 확정 체력·출혈 상태로 수렴해야 한다
```
### 붕대 치료 세션 (동일 파일)
RED:
```
[Failed]: 붕대 1개 소비가 양쪽에 복제되어야 한다
[Failed]: 치료받는 쪽(클라이언트 기계의 로컬 아바타) 이동이 잠겨야 한다
```
GREEN: 9/9. 경계 조건 포함 — 세션 없는 커밋 거부, 홀드 미달(즉시 커밋 변조) 거부,
붕대 중간 소실 시 커밋 거부, 치료 중 대상 사망 시 세션 해제 + 원격 잠금 해제, 환자 이탈 시 세션 정리.
(거부-계열 부정 테스트의 검증력은 아래 뮤테이션으로 증명했다.)

## 3. 뮤테이션 자가검증 (심고 → 실패 확인 → 원복 → 통과 확인)

| 뮤테이션 | 심은 결함 | RED 증거 (실제 출력) | 원복 후 |
|---|---|---|---|
| 1. 호스트 아이템 소유권 검사 제거 | `world_item.gd` 의 `count -= added` 삭제 (소유권 미이전) | `[6] expected to equal [3]: 총합 보존 — 복제 발생`, `정확히 한 명만 획득해야 한다` 등 4 tests 실패 | All tests passed |
| 2. 클라이언트도 smell_emitted 발신 | `health_component.gd` 권위 게이트 삭제 | GUT: `emit count of [2] to equal [1]` 실패. 하네스: `blood 발신 11회 (기대 6회)` → exit 1 | All tests passed |
| 3. 클라이언트 피해량 그대로 신뢰 | `net_survival.gd` 클램프 제거 | `변조된 10000 피해가 적용됐다면 죽었을 것이다`, `[0.0] expected to be > than [72.0]` 실패 | All tests passed |

## 4. 헤드리스 2인 협동 하네스 (실행 근거)

`scripts/survival/two_player_coop_harness.gd` — 실제 main.tscn 2개 + ENet 루프백, 전 구간 자동 판정, exit 0:
```
[t=  0.0s] main.tscn 2개 로드 완료. NetPickup/NetSurvival 배선 확인
[t=  0.6s] 경합 결과: 호스트 3개 / 클라이언트(호스트 권위) 0개        ← 정확히 1명, 총합 3 보존
[t=  0.7s] 원격 획득 복제 완료 (돌 +2)
[t=  0.7s] 부상 확정: health=75.0 (클램프 25 적용), bleeding=true    ← 10000 주장 거부
[t=  3.7s] blood 발신 6회 (기대 6회, 호스트 단독 발신 기준)
[t=  3.7s] 호스트 격자 환자 위치 농도 73.2, 클라 복제본 bleeding=true
[t=  3.7s] 치료 홀드 중 양쪽 이동 잠금 확인
[t=  5.7s] 치료 확정 복제 완료: 지혈 + 붕대 소비 + 잠금 해제
[t=  7.7s] 냄새 정지 확인: 발신 0회, 격자 73.2 → 0.0
[t=  7.8s] === 2인 협동 하네스 성공 ===
```
CI 관문으로 등록: `.github/workflows/ci.yml` "Two-player co-op harness".

## 5. 최종 회귀 (전부 이 커밋 시점 실측)

| 관문 | 결과 |
|---|---|
| `--import` 선행 + GUT 전체 | 31 scripts / 185 tests / 599 asserts / 실패 0 / exit 0 (기준선 29/170/510 무손상 + 신규 2 scripts/15 tests) |
| 조용한 스킵 대조 | 디스크 test_*.gd 31개 == GUT 리포트 31개 |
| 1주차 목표 장면 `goal_scene_replay.gd` | exit 0 (`=== 목표 장면 재현 성공 ===`) |
| W2-T1 2인 하네스 | exit 0 |
| W2-T4 network conditions 하네스 | exit 0 |
| W2-T2 협동 하네스 | exit 0 |

## 6. 남은 것 / 알려진 한계

- 클라이언트 인벤토리는 이벤트 복제본이다 — 재접속(120초 슬롯) 시 인벤토리 재동기화 스냅샷은 다음 태스크.
- 모닥불(props) 상호작용은 아직 로컬 판정이다 — 아이템·치료와 같은 패턴으로 얹으면 된다 (소유권 밖이라 미변경).
- `request_hurt` 는 디버그 부상 전용 경로다. 랩터 공격 피해는 W2-T3 방식대로 호스트에서 직접 판정하면 되고 RPC 가 필요 없다.

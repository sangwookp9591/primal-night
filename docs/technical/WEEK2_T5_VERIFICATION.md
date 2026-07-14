# W2-T5 검증 리포트 — 모닥불 네트워크화 + 재접속 재동기화 + 목표 장면 전 구간 통합 하네스

작성: 2026-07-14 (워커 task_2150fcd4af12)
기준선: 8604a18 (GUT 31 scripts / 185 tests / 599 asserts / 실패 0, 관문 5종 exit 0)

## 1. 산출물 요약

| 항목 | 파일 | 커밋 |
|---|---|---|
| 모닥불 호스트 권위 + 복제 | scripts/props/net_campfire.gd, campfire.gd, campfire_site.gd, tests/props/test_net_campfire.gd | feat(props) |
| 재접속 전체 상태 재동기화 | scripts/net/net_resync.gd, net_movement.gd(teleport_avatar), tests/net/test_net_resync.gd | feat(net) |
| 재접속 피어 RpcGuard 재등록 (기존 버그) | scripts/items/net_pickup.gd, scripts/survival/net_survival.gd (각 1줄) | feat(net)에 포함 |
| 랩터 다중 플레이어 인식 | scripts/creature/raptor.gd, tests/creature/test_raptor_two_players.gd | feat(creature) |
| ★ 목표 장면 전 구간 통합 하네스 | scripts/net/two_player_goal_scene_harness.gd | test(net) |
| CI 관문 (통합 하네스 5회 연속) | .github/workflows/ci.yml | test(net) |

모든 로직은 RED(실패 관측) → GREEN(최소 구현) → 원자적 커밋 순서로 만들었다.

## 2. TDD RED/GREEN 증거

### 2.1 NetCampfire (tests/props/test_net_campfire.gd)

RED (스텁 상태, 5개 테스트 전부 기능 부재로 실패 — 190 중 185 통과):

```
- test_client_build_replicates_to_both_machines
    [Failed]: 모닥불이 양쪽 기계에 설치·점화되어야 한다
    [Failed]: [3] expected to equal [0]:  호스트가 권위적으로 돌을 소비한다
- test_same_frame_contest_exactly_one_campfire_single_material_spend
    [Failed]: [2] expected to equal [1]:  경합에서도 campfire_lit 은 정확히 1회 (호스트 단독)
- test_build_without_materials_is_rejected_then_control_build_succeeds
    [Failed]: 재료가 있으면 같은 RPC 로 설치가 확정·복제되어야 한다
- test_build_beyond_distance_is_rejected
    [Failed]: 사거리 안 자리는 설치가 확정·복제되어야 한다
- test_fuel_timer_is_host_owned_and_extinguish_replicates
    [Failed]: 호스트 설치가 양쪽에 복제되어야 한다
---- 5 failing tests ----
```

RED 상태에서 이미 클라이언트 중복 발신([2] expected [1])이 잡히는 것을 확인 —
테스트가 뮤테이션 1(클라 발신)을 실제로 감지함을 사전 증명.

GREEN: `Scripts 32 / Tests 190 / Passing 190 / Asserts 637 — All tests passed!`
(기존 test_campfire.gd 싱글 경로 무손상, goal_scene_replay exit 0 확인)

### 2.2 NetResync (tests/net/test_net_resync.gd)

RED (스텁 상태, 4개 중 3개 실패):

```
* test_reconnect_within_grace_restores_client_replica
    [Failed]: 재접속한 클라이언트가 인벤토리를 되찾아야 한다
* test_reconnect_after_despawn_restores_saved_state
    [Failed]: 보관된 인벤토리가 새 아바타에 복원되어야 한다
    [Failed]: 출혈 상태가 복원되어야 한다
    [Failed]: [100.0] expected to equal [70.0] +/- [3.0]:  체력이 복원되어야 한다
    [Failed]: [64.0] expected to equal [400.0] +/- [8.0]:  위치가 복원되어야 한다
* test_reconnected_peer_intents_work_again
    WARNING: RpcGuard: 거부 rpc=request_pickup sender=1366269002 reason=unknown_sender
    WARNING: RpcGuard: 거부 rpc=request_hurt  sender=1366269002 reason=unknown_sender
    [Failed]: 재접속한 피어의 줍기 의도가 다시 동작해야 한다 (RpcGuard 재등록)
    [Failed]: 재접속한 피어의 부상 의도가 다시 동작해야 한다 (RpcGuard 재등록)
1/4 passed.
```

★ RED 가 W2-T2/T4 통합의 **기존 버그**를 드러냈다: NetPickup/NetSurvival 이
`player_reconnected` 를 구독하지 않아 재접속 피어(새 peer id)의 모든 의도 RPC 가
`unknown_sender` 로 거부된다. 각 1줄(`player_reconnected.connect(_on_player_joined)`)로 수정.

중간 실패 1건: 위치 복원이 스폰 위치(64,0)로 되돌아감 — 원인은 MovementAuthority 의
검증 기준 위치가 스폰 위치에 남아 복원 직후의 이동 의도가 텔레포트로 오판·거부되는 것.
`NetMovement.teleport_avatar()` (위치 + 검증 기준 동시 이동)로 해결.

GREEN: `Scripts 33 / Tests 194 / Passing 194 / Asserts 680 — All tests passed!`

### 2.3 랩터 다중 플레이어 인식 (tests/creature/test_raptor_two_players.gd)

RED (기존 로직 = 그룹 첫 노드 1명 고정, 3개 전부 실패):

```
* test_chases_the_nearest_visible_player_not_the_first_in_group
    [Failed]: [VECTOR2(80.0, 0.0)] expected to equal [VECTOR2(50.0, 0.0)]:  가장 가까운 플레이어를 추격해야 한다
* test_flees_only_when_every_visible_player_is_protected
    [Failed]: [3(FLEE)] expected to equal [2(CHASE)]:  비보호 동료가 보이는 동안에는 물러나면 안 된다
    [Failed]: [0(WANDER)] expected to equal [3(FLEE)]:  두 명 다 불 반경 안이면 랩터가 물러나야 한다
* test_ignores_players_from_another_machine_branch
    [Failed]: [2(CHASE)] expected to equal [0(WANDER)]:  다른 기계의 플레이어는 지각하지 않는다
0/3 passed.
```

GREEN: `Scripts 34 / Tests 197 / Passing 197 / Asserts 687 — All tests passed!`
- goal_scene_replay(1주차 싱글 목표 장면) exit 0, two_player_raptor_harness exit 0 — 무손상.

## 3. ★ 목표 장면 전 구간 통합 하네스 (scripts/net/two_player_goal_scene_harness.gd)

한 실행으로 잇는 구간 (exit 0 / 실패 시 exit 1, 단계별 로그):

1. 호스트 방 생성 → 클라이언트 로컬 참가 (친구 초대는 Steam 몫 — 로컬 대체)
2. 두 명이 계곡 탐색 — 실제 입력 액션으로 둘 다 이동, 양방향 위치 복제 수렴 검증
3. 클라이언트 부상 — 변조 피해량 10000 주장 → 호스트 클램프 → 출혈 복제
4. 호스트 랩터가 냄새 추적: 배회 → 조사(t=8.4s) → 추격(t=14.1s), 클라이언트 상태 복제
5. 호스트가 월드 붕대 획득 → 홀드 치료 → 호스트 확정 → 냄새 발신 정지 (120프레임 관측 0회)
6. 클라이언트가 재료 수집(NetPickup 경로) → 지정자리 설치 홀드 → NetCampfire 의도
   → 호스트 검증·확정 → 양쪽 점화, campfire_lit 정확히 1회, 재료 1회 소비
7. ★ 결말: 점화로 랩터 후퇴 → 호스트만 불 밖에 노출 → **랩터가 물러나지 않고
   노출된 호스트를 추격 (한 명만 보호 ≠ 안전)** → 호스트도 불 반경 안
   → **전원 보호 → FLEE, 불과의 거리 271→472px 증가**, 클라이언트 랩터 상태 복제
8. 에필로그: 클라이언트 이탈 → 동일 PlayerId 재접속 → 인벤토리(돌 2) 복원,
   호스트 권위 총합 불변(복제·소실 0), 출혈 없음, 재접속 후 줍기 의도 재동작

### 결정성 (WEEK1_VERIFICATION.md B-01 준수)

5회 연속 실행 전부 exit 0, 시뮬 시간 25.0s 동일:

```
run 1: exit=0 ... run 5: exit=0
상태 전환 순서 5회 모두 동일 (7전환):
wander→investigate→chase→flee→wander→chase→flee→wander
```

로그 diff 는 무작위 ENet peer id(client_id) 한 줄뿐 — 프레임 타이밍·좌표·판정 전부 동일.
CI 에 5회 연속 관문으로 추가 (Two-player goal scene harness (full E2E x5)).

## 4. 뮤테이션 자가검증 (심고 → RED → 원복 → GREEN)

### M1. 클라이언트에서도 campfire_lit 발신 (campfire.gd 의 is_server 게이트 제거)

RED — GUT 2건 + 통합 하네스 실패:
```
[Failed]: [2] expected to equal [1]:  campfire_lit 은 호스트에서만 1회 — 클라이언트도 발신하면 랩터가 불을 2개로 인식한다
[Failed]: [2] expected to equal [1]:  경합에서도 campfire_lit 은 정확히 1회 (호스트 단독)
Failing Tests 2
하네스: campfire_lit #1, campfire_lit #2 →
=== 실패: campfire_lit 이 2회 발신됐다 — 호스트 단독 1회여야 한다 (랩터 중복 인식) ===
```

### M2. 모닥불 재료 검증 제거 (net_campfire.gd _host_build 의 consume 검사 무시)

RED — 동시 설치·변조 테스트가 잡음:
```
[Failed]: Expected [Campfire:...] to be NULL:  재료 없는 변조 설치 주장은 거부되어야 한다
[Failed]: Expected [Campfire:...] to be NULL:  거부된 설치는 클라이언트에도 복제되지 않는다
[Failed]: [3] expected to equal [0]:  대조군 설치가 재료를 소비한다
Failing Tests 1 (test_build_without_materials_is_rejected_then_control_build_succeeds)
```

### M3. 재접속 스냅샷에서 인벤토리 누락 (net_resync.gd 빈 배열 전송)

RED — GUT 2건 + 통합 하네스 에필로그 실패:
```
[Failed]: 재접속한 클라이언트가 인벤토리를 되찾아야 한다  (grace/despawn 두 경로)
Failing Tests 2
하네스: === 실패: 재접속한 클라이언트가 인벤토리를 되찾지 못했다 ===
```

세 뮤테이션 모두 원복 후 최종 회귀에서 GREEN (아래 5절).

## 5. 최종 회귀 (원복 상태)

```
--import 에러 0
GUT: Scripts 34 / Tests 197 / Passing 197 / Asserts 687 / 실패 0
관문: goal_scene_replay exit 0
      two_player_harness exit 0
      two_player_raptor_harness exit 0
      network_conditions_harness exit 0
      two_player_coop_harness exit 0
신규: two_player_goal_scene_harness 5회 연속 exit 0 (+ 결정성 검증의 5회와 별도)
```

## 6. 소유권 밖 수정 (사전 통지 완료, 다른 워커 전원 완료 상태)

| 파일 | 수정 내용 | 근거 |
|---|---|---|
| scripts/creature/raptor.gd | 다중 플레이어 대상 선택 (최근접 비보호, 전원 보호 시 후퇴, 기계 필터) | 태스크 ★요구: "랩터가 두 플레이어 모두를 인식" — 기존 구조(첫 노드 1명)로는 불가능 |
| tests/creature/test_raptor_two_players.gd (신규) | 위 로직의 RED/GREEN 테스트 | TDD 의무 |
| scripts/items/net_pickup.gd, scripts/survival/net_survival.gd | player_reconnected → RpcGuard 재등록 각 1줄 | RED 로 증명된 기존 버그 — 재접속 후 모든 의도 RPC 사망 |
| scripts/net/net_movement.gd | teleport_avatar() 공개 API 추가 | 재접속 위치 복원이 이동 검증에 오판·거부되는 문제 (scripts/net/** 는 소유) |

## 7. 남은 것 / 다음 태스크 후보

- 모닥불 소등 복제는 연료 소진(호스트 타이머) 기준. 하네스의 목표 장면에는 소등
  시나리오가 없어 GUT(test_fuel_timer_is_host_owned_and_extinguish_replicates)만 지킨다.
- 재접속 30초 유예 경로의 E2E 는 하네스 에필로그가, 30~120초(아바타 재생성) 경로와
  120초 만료(새 플레이어) 경로는 GUT 이 지킨다 (실시간 대기 없이 tick 전진).
- RpcGuard 반복 위반 연결 종료(rpc_guard.gd ponytail 주석)는 여전히 미착수 — 기존 항목.

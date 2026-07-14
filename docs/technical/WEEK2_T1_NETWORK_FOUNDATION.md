# W2-T1 — 네트워크 기반: 어댑터 경계 + 호스트 권한 + 2인 이동 동기화 + 헤드리스 2인 하네스

- 작성일: 2026-07-14
- 브랜치: 초기작업
- 기준 문서: 설계서 7.1~7.4, 9.1~9.3 / 성능 문서 4.6, 14

## 1. 무엇을 만들었나

| 산출물 | 파일 | 요약 |
|---|---|---|
| 세션 어댑터 경계 | `scripts/net/session_service.gd` | `@abstract SessionService` — host/join/leave, PlayerId(StringName), peer↔PlayerId 변환, joined/left/ended 신호. 게임 코드는 이것 + 표준 MultiplayerAPI 만 본다 |
| 로컬 구현 | `scripts/net/local_session_service.gd` | ENet 은 이 파일 안에만 존재. 참가자 목록·ID 변환을 MultiplayerAPI 에서 유도하는 무상태 구현 — 접속 신호 순서 경쟁 원천 차단 |
| 호스트 이동 검증 | `scripts/net/movement_authority.gd` | 직전 권위 위치 대비 이동 예산(`max_speed × elapsed × tolerance`, 최소 바닥) 텔레포트 검사. NaN/INF 거부. 위반 계수 |
| RPC 보안 골격 | `scripts/net/rpc_guard.gd` | RPC 별 허용 발신자(호스트 전용)·초당 빈도·페이로드 상한. 미등록 RPC·비구성원 기본 거부. 연결별 위반 계수 + 구조화 로그(IP 제외) |
| 이동 동기화 | `scripts/net/net_movement.gd` | 클라 의도(비신뢰 최신값, 멈추면 미전송) → 호스트 RpcGuard + MovementAuthority 검증 → 권위 확정 → 10Hz 비신뢰 스냅샷 복제. 자기 아바타는 서버 확정에서 크게 벗어날 때만 보정 스냅 |
| 규칙 수치 | `scripts/net/net_config.gd` + `resources/net/net_config.tres` | 포트·허용 배수·빈도/페이로드 상한·스냅샷 주기(10Hz) 등 전부 리소스 |
| 게임 씬 연결 | `scenes/main.tscn` | NetSession + Players + NetMovement 배선. 싱글은 peer 없는 동일 흐름 (네트워크 활동 0) |
| 2인 하네스 | `scripts/net/two_player_harness.gd` | 한 프로세스, `SceneTree.set_multiplayer` 브랜치 2개에 실제 main.tscn 2개 + 실제 루프백 소켓. 접속→스폰→이동→동기화→변조 거부→이탈 전 구간 자동 판정, 실패 시 exit 1 |
| CI 관문 | `.github/workflows/ci.yml` | `Two-player headless harness (E2E)` 스텝 추가 |

## 2. 경계 설계 — Steam 이 들어와도 게임 코드가 안 바뀌는 이유

- 게임 로직 의존: **SessionService(추상) + 표준 MultiplayerAPI(rpc)** 뿐. `ENetMultiplayerPeer` ↔ `SteamMultiplayerPeer` 는 둘 다 `MultiplayerPeer` — peer 교체는 `LocalSessionService` → `SteamSessionService` 노드 교체(= main.tscn 한 노드) 로 끝난다.
- **PlayerId = StringName**: ENet 은 peer id 문자열, Steam 은 SteamID64 문자열. int peer id 로는 64비트 SteamID 를 못 담는다. 재접속 슬롯(설계서 7.3) 식별자도 이 PlayerId.
- Steam 에만 있는 개념(로비 초대장)은 `join_session(invite: Variant)` 뒤로 숨겼다 — 로컬은 `"ip:port"`, Steam 은 로비 ID.
- 경계 관문: `grep -ri enet scripts/ scenes/` → 실 매치는 `scripts/net/local_session_service.gd` (허용된 구현 내부) 뿐. 나머지 출력은 엔진 클래스명 `SceneTree` 의 대소문자 무시 부분 문자열(`...eneT...`) 오탐이다.

## 3. 호스트 권한 골격 (설계서 7.2) — 다음 태스크가 얹는 자리

흐름: `클라이언트 의도 → RpcGuard(발신자/빈도/페이로드) → 대상은 발신자 peer 에서 유도(남의 아바타 조작 불가) → MovementAuthority(거리 검증) → 권위 확정 → 복제`.
공룡 AI·아이템·제작·피해 복제는 이 파이프라인의 검증 단계에 각자의 규칙(거리·쿨다운·소유권·재료)을 추가하면 된다.

## 4. 완료 판정 — 실행 근거

### 4.1 `--import` 선행 GUT 전체 (기존 128 유지)

```
Scripts 28 / Tests 157 / Passing 157 / Asserts 459 — All tests passed!
(기준선 24/128/362 + 신규 net 4스크립트/29테스트/97asserts)
```

### 4.2 1주 차 목표 장면 3연속

```
goal replay 1 exit=0 / goal replay 2 exit=0 / goal replay 3 exit=0
```

### 4.3 헤드리스 2인 하네스 (`artifacts/two_player_harness_w2t1.log`)

```
[t=  0.1s] 접속 완료. host players=[&"1", &"…"] / client players=[&"1", &"…"]
[t=  0.1s] 스폰 완료. host측=(-320, 200) client측=(-320, 200)
[t=  2.8s] 이동량: 호스트 180px / 클라이언트 180px
[t=  2.8s] 동기화 오차: 호스트→클라 0.0px / 클라→호스트 0.0px (허용 8px)
[t=  3.5s] 호스트측 아바타 이탈량 0px, 위반 기록 N≥1건 → 보정 완료
[t=  3.5s] 이탈 정리 완료. host players=[&"1"]
=== 2인 하네스 성공 === (exit 0, 5연속 재실행 전부 exit 0)
```

### 4.4 ENet 비노출

`grep -ri enet scripts/ scenes/` 실 매치 = `local_session_service.gd` 내부만 (2절 참조).

### 4.5 뮤테이션 자가검증 — 호스트 권한 검사 제거

뮤테이션: `submit_move_intent` 에서 `_authority.submit(...)` 를 `claimed_position` 으로 교체 (클라이언트 좌표를 그대로 신뢰).

RED (뮤테이션 상태 — 두 계층 모두 포착):
```
GUT  test_teleport_claim_is_rejected_and_client_is_corrected:
     [5000.0] expected to be < than [100.0] / [0] expected to be > than [0] …
하네스: [t=3.5s] 호스트측 아바타 이탈량 5000px, 위반 기록 0건
        === 2인 하네스 실패: 호스트가 텔레포트 주장을 수용했다 (5000px) === (exit 1)
```

GREEN (원복 후): GUT net 29/29, 하네스 exit 0.

### 4.6 TDD RED→GREEN 기록 (커밋 단위)

| 단위 | RED (실패 확인) | GREEN |
|---|---|---|
| MovementAuthority | 7/7 실패 (스텁: `[VECTOR2(0,0)] expected to equal [VECTOR2(30,0)]` 등) | 7/7, asserts 16 |
| RpcGuard | 9/10 실패 (통과 1건은 전부-거부 스텁에서도 성립하는 '거부 기대' 테스트) | 10/10, asserts 21 |
| LocalSessionService | 7/7 실패 (`ERR_UNCONFIGURED`, 신호 미발신) | 7/7, asserts 28 |
| NetMovement | 5/5 실패 (스폰 안 됨, 동기화 없음) | 5/5, asserts 32 |
| main.tscn 연결 + 하네스 | 하네스 exit 1: `main.tscn 에 NetSession 노드가 없다` | 하네스 exit 0 |

## 5. 알려진 한계 → 다음 태스크

- 클라이언트 이탈 시 **즉시 제거** — 설계서 7.3 의 '30초 제자리 잔류'와 120초 재접속 슬롯은 다음 태스크 (식별자는 이미 PlayerId 로 준비됨).
- 호스트는 클라 이동의 **거리만** 검증 — 벽 통과(경로) 검증 없음. 협동 게임 위협 모델에서 후순위.
- 클라이언트 아바타의 소음/냄새를 호스트 랩터가 감지하지 못함 — 냄새·소리 이벤트 복제는 다음 태스크 (설계서 7.2 목록의 나머지).
- 판정 결정성 이슈 1건 발견·수정: 텔레포트 1회 주입은 10Hz 보정 스냅샷이 의도 전송보다 먼저 도착하면 로컬에서 되돌려져(호스트는 속은 적 없음) 위반 기록이 안 남는 경합 — 변조 위치 다중 프레임 강제 주입으로 해결 (84bd84a).

## 6. 커밋 목록

```
211da77 feat(net): MovementAuthority — 호스트 텔레포트 검증 (설계서 7.4)
9ad6cdf feat(net): RpcGuard — RPC 보안 골격 (설계서 7.4)
aef593b feat(net): SessionService 추상 경계 + LocalSessionService 구현 (설계서 9.1)
7cbb9a3 feat(net): 2인 이동 동기화 — 의도 전송, 호스트 권위 확정, 스냅샷 복제
325a41e feat(net): 네트워크를 실제 게임 씬에 연결 + 헤드리스 2인 하네스 + CI 관문
7015157 docs(net): 게임 로직 주석에서 백엔드 이름 제거 — 경계 관문(grep) 명확화
84bd84a fix(net): 텔레포트 변조 판정 결정성 — 변조 위치 다중 프레임 강제 주입
```

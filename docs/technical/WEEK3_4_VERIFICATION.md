# W3~4 검증 리포트 — 소리·냄새 기반 회색 상자 생존 루프

작성: 2026-07-14 (워커 task_884ad7dcd3ec)
기준선: W3~4 계획 수립 시점 GUT `34 scripts / 199 tests / 696 asserts / 실패 0`
최종 실측: `/opt/homebrew/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
→ `46 scripts / 266 tests / 983 asserts / 실패 0`, 실행 시간 65.926s.

## 1. 결론

3~4주차 목표였던 "소리·냄새와 랩터 1종이 작동하는 회색 상자 생존 루프"는 자동 검증 기준을 충족했다. 고정 시드 4001~4010 감지 루프 하네스가 10/10 PASS 했고, 각 시드에서 소리 조사, 냄새 조사, 랩터 상실, 모닥불 회피 성공을 모두 관측했다. 5주차 중단 기준인 "소리·냄새로 공룡을 예측하고 피하는 플레이"의 구성요소는 현재 테스트와 하네스로 전부 검증된다.

## 2. 태스크별 산출물

| 태스크 | 커밋 | 커밋 메시지 | 주요 산출물 |
|---|---|---|---|
| W3-T2 | d85a509 | feat(session): 회색 상자 감지 루프 세션 골격 (W3-T2) | `loop_objective`, `session_clock`, main 씬 세션 연결, 세션 GUT. 9 files, +444/-1 |
| W3-T3 | 03ab409 | feat(senses): 행동별 소리 프로필과 발신 API 추가 | `NoiseProfile`, `NoiseEmitter`, 행동별 `data/senses/*.tres`, 플레이어/상호작용 발신. 17 files, +210/-1 |
| W3-T4 | 97416c1 | feat(senses): raw_meat 냄새 원천 등록 추가 | `SmellSource`, `SmellGrid` 등록 원천, raw_meat 바닥/보유 냄새 테스트. 9 files, +213 |
| W3-T5 | cd3a3b4 | feat(ui): 바람/소리/랩터 경보 최소 HUD 추가 | `SenseIndicatorModel`, HUD 바람/소리/랩터 경보, 모델 테스트. 6 files, +214/-3 |
| W3-T6 | 77529f6 | feat(creature): 랩터 조사 품질 — 상실·재탐색·관심도 (W3-T6) | 랩터 조사 훑기, 관심도, 재탐색, 상태 테스트. 6 files, +298/-15 |
| W4-T1 | 99e67cf | feat(player): 은신 최소 구현 — 웅크리기와 수풀 소음 변화 | crouch 입력, sneak/bush noise profile, `StealthZone`, 은신 테스트. 9 files, +234/-5 |
| W4-T2 | 5e18bfe | feat(items): 미끼 투척 회피 도구 추가 | `ThrowableBait`, bait item, 호스트 권위 투척, 소리+냄새 원천 테스트. 7 files, +252 |
| W4-T3 | 671d3e0 | feat(survival): 생존 수치 4종 최소 모델 — 체온·수분·포만·피로 (W4-T3) | `SurvivalStats`, HUD 단계, NetSurvival 복제, 피로/체온 테스트. 10 files, +567/-13 |
| W4-T4 | d78f4d9 | test(senses): 회색 상자 감지 루프 하네스 — 고정 시드 10회 headless 실주행 (W4-T4) | `sense_loop_harness`, CI 관문 추가. 3 files, +248 |
| W4-T5 | abffe5d | perf(core): W3~4 감지 루프 성능 회귀 게이트와 기준선 (W4-T5) | 성능 기준선 CSV/JSON, perf budget GUT, baseline 캡처 도구. 7 files, +2521 |
| 리뷰A 후속 | ffe507a | fix(senses): 소음 반경 단일화와 권위 검사 보강 | NoiseProfile.radius 단일 소스, null source 권위 우회 차단. 8 files, +24/-24 |
| 리뷰A 후속 | d168a1e | refactor(items): 냄새 원천을 아이템 데이터로 전환 | raw_meat 하드코딩 제거, ItemData 냄새 필드, SmellGrid keys allocation 축소. 5 files, +39/-11 |
| 리뷰A 후속 | 345df9e | fix(session): 냄새와 미끼를 위험 노출로 반영 | raw_meat 보유와 bait smell을 LoopObjective 위험 노출로 반영. 2 files, +37/-1 |
| 리뷰A 후속 | 1c92699 | test(creature): 반복 소리 조사 목표 갱신 의도 고정 | 랩터 `>=` 관심도 의도 고정 테스트. 1 file, +23 |
| 리뷰A 후속 | cdbc032 | feat(net): 재접속 생존수치 보존 | NetResync에 SurvivalStats 4수치 보관/복원 추가. 3 files, +45/-4 |
| 리뷰B-2 후속 | 6494e1c | fix(net): 원격 아바타 은신 소음 호스트 권위 반영 (중대) | remote stance intent, 호스트 권위 원격 소음 profile 반영, net 테스트. 5 files, +305/-13 |
| 리뷰B-2 후속 | 8f4b7bc | fix(ui): 랩터 없는 화면의 매 프레임 재귀 트리 스캔 제거 (경미) | HUD 랩터 스캔 interval화, 회귀 테스트. 3 files, +59/-2 |

## 3. 교차 리뷰 결과

### 리뷰A

- 중대 3건, 경미 4건 확인.
- 해소 커밋: `ffe507a`, `d168a1e`, `345df9e`, `1c92699`, `cdbc032`.
- 랩터 소리 관심도 `>=` 동작은 설계 의도로 판정했다. 반복 발신 중에는 최신 청취 위치로 갱신하고, 발신이 멈추면 목표가 고정되는 테스트를 `1c92699`로 추가했다.

### 리뷰B-1

- 블로커 없음.
- 특별 확인 2건 통과: W4-T5 성능 기준선/게이트가 예산 안에 있고, CI 기존 관문을 대체하지 않았다.

### 리뷰B-2

- 중대 1건: 원격 클라이언트 웅크리기/수풀 상태가 호스트 권위 소음에 반영되지 않았다.
- 해소: `6494e1c`에서 NetMovement가 stance intent를 보내고, 호스트가 원격 소음 발신 시 권위적으로 profile을 고른다.
- 경미 1건: 랩터가 없는 HUD 화면에서 매 프레임 재귀 트리 스캔 가능.
- 해소: `8f4b7bc`에서 랩터 스캔을 interval 재시도로 낮추고 테스트를 추가했다.

## 4. 감지 루프 하네스

실행: `/opt/homebrew/bin/godot --headless --path . -s scripts/senses/sense_loop_harness.gd`

결과: 고정 시드 4001~4010 전부 PASS.

| 판정 항목 | 의미 | 결과 |
|---|---|---|
| 소리 조사 | 랩터가 소리 단서로 WANDER → INVESTIGATE | 10/10 |
| 랩터 상실 | 조사 지점 훑기 소진 후 WANDER 복귀 | 10/10 |
| 냄새 조사 | 랩터가 냄새 단서로 WANDER → INVESTIGATE | 10/10 |
| 회피 성공 | CHASE 중 모닥불 보호로 FLEE 진입 | 10/10 |

CI에는 `Sense loop detection harness (10 seeds)`가 추가됐다. 기존 `Run GUT`, goal scene replay 3회, two-player harness, network conditions harness, two-player co-op harness, two-player goal scene harness 5회는 대체하지 않고 유지된다.

## 5. 성능 기준선

기준 파일: `docs/technical/BASELINE_W3_4_SENSE_LOOP.json`

| 항목 | 실측 |
|---|---:|
| frame p95 | 6.944 ms |
| frame p99 | 7.407 ms |
| frame max | 150.0 ms |
| 평균 FPS | 142.616 |
| ai p95 | 0.070 ms |
| ai max | 0.112 ms |
| scent p95 | 0.053 ms |
| scent max | 0.061 ms |
| smell active cells max | 13 |
| noise events total | 45 |

예산 여유: AI와 scent 갱신 p95가 0.1ms 안팎으로 낮고, 활성 냄새 셀 최대 13개라 현재 회색 상자 루프에서는 성능 예산에 충분한 여유가 있다. 단 이 기준선은 macOS Apple M5 headless 개발기 로컬 회귀 게이트이며, Windows 최소사양 출시 판정 수치는 아니다.

## 6. 최종 회귀

```
GUT: Scripts 46 / Tests 266 / Passing 266 / Asserts 983 / 실패 0
Sense loop harness: seed 4001~4010 10/10 PASS
```

계획 수립 시점 기준선은 `34 scripts / 199 tests / 696 asserts / 실패 0`이었다. 3~4주차 종료 시점에는 테스트가 67개 증가했고, 신규 감각 루프 하네스와 성능 게이트까지 포함된다.

## 7. 잔여 기술 부채 / 다음 주차 이월

| 항목 | 이월 사유 |
|---|---|
| 병렬 Godot 실행 시 `tests/net` ENet 포트 경합 간헐 실패 | CI 직렬화 또는 포트 분리 검토 필요 |
| `sense_loop_harness`가 EventBus 직접 주입 | 생산자(`NoiseEmitter`/`SmellSource`) 회귀는 GUT 테스트에 의존 |
| 냄새 원천 아이템 다중 보유 시 첫 번째만 등록 | 현재는 표현 문제. 강도 합산/우선순위는 W5 이후 |
| 신규 스폰 직후 미세 피로 스파이크(~0.75/100) | 실질 영향 없음. 필요 시 spawn baseline reset 범위 확대 |
| `NoiseEmitter` 자체 계측 샘플 없음 | 현재는 이벤트 수 상한/병합 테스트로 대체 |
| `SurvivalStats`가 `player.tscn`에 노출되지 않고 코드 `add_child` | 씬 편집 가시성보다 병렬 작업 충돌 회피를 우선 |
| 랩터 무리/측면 포위, 수분/포만 행동 효과 | 5주차 이후 설계 범위 |
| `GameData` 아이템 등록이 수동 | W5에 manifest 또는 data directory scan 검토 |

## 8. 5주차 중단 기준 대비

현재 상태는 5주차 말 중단 기준의 핵심 문장인 "소리·냄새로 공룡을 예측하고 피하는 플레이"를 자동 검증한다. 소리는 행동별 `NoiseProfile`, 은신/수풀/원격 stance, 미끼 착지 소리로 구성됐고, 냄새는 출혈·raw_meat·bait 원천과 바람 이류로 구성됐다. 랩터는 단서 조사, 상실, 재탐색, 추격, 모닥불 회피를 갖고 있으며, `sense_loop_harness`가 이 흐름을 10개 고정 시드에서 반복 검증한다.

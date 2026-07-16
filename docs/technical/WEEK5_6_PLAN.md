# PRIMAL NIGHT W5~6 작업 범위 갭 분석 및 우선순위 제안

- 작성일: 2026-07-16 (Asia/Seoul)
- 범위: 분석 및 계획 전용. 이 문서 외 코드 수정·커밋 없음.
- 기준 문서: `docs/superpowers/specs/2026-07-13-primal-night-design.md`, `docs/technical/WEEK3_4_PLAN.md`, `docs/technical/WEEK3_4_VERIFICATION.md`, `docs/technical/2026-07-13-performance-budget-and-regression-policy.md`, `docs/technical/2026-07-14-asset-generation-policy.md`
- 직접 재검증: Godot `4.7.stable.official.5b4e0cb0f`, GUT `46 scripts / 266 tests / 983 asserts / 실패 0` (66.014초), 감지 루프 하네스 seed `4001~4010` `10/10 PASS`
- 기준 브랜치/커밋: `5-6주차-작업-진행` / `6d5e64a`

## 1. 결론

5주차의 최단 경로는 새 공룡이나 새 생존 수치를 추가하는 일이 아니다. 현재 자동 하네스는 소리 조사, 냄새 조사, 관심 상실, 모닥불 회피라는 **상태 전환**을 검증하지만, `EventBus`에 단서를 직접 주입하고 플레이어가 위험을 무시해도 불이익이 없으므로 **사람이 단서를 읽고 선택해서 살아남는 재미**까지 증명하지 못한다. 실제 `main.tscn`에도 날고기·미끼가 없고, 미끼 투척 입력·목표 표시·세션 결과 표시가 없으며, `LoopObjective`는 위험 노출 플래그 뒤 도착만 하면 성공한다.

따라서 W5는 실제 입력으로 미끼와 냄새 짐을 쓰게 만들고, 랩터에게 잡히면 실패하는 회색 상자 규칙, 시간·목표·결과 피드백, 생산자 경로 하네스, 플레이 세션 기록을 더한 뒤 10회 사람 플레이로 중단 기준을 판정한다. 자동 `10/10 PASS`는 회귀 관문일 뿐 재미 판정으로 사용하지 않는다.

W6은 W5 재미 관문을 통과한 경우에만 연다. 첫 절편은 **16칸·무게 제한 인벤토리 → 다리 열상과 붕대 치료 → 날고기를 미끼로 만드는 퀵 제작 1종 → 3일 시계 골격**이다. 기존 모닥불을 첫 거점 설비로 재사용하고, 새 설비·새 공룡·제작 UI 전체·부상 6종 전체는 만들지 않는다.

## 2. 설계 대비 현재 구현 갭

| 설계 항목 | 확인한 현재 구현 | 이번 블록의 갭/판정 |
|---|---|---|
| 3~5주 회색 상자 감지-회피 루프 | `NoiseProfile`/`NoiseEmitter`, 4Hz 활성 셀 `SmellGrid`, 랩터 `WANDER/INVESTIGATE/CHASE/FLEE`, 웅크리기·수풀·미끼·모닥불, 12분 `SessionClock`, 10시드 하네스가 존재 | 자동 상태 전환은 완성. 실제 사람 플레이의 예측·선택·실패 가능성은 미검증 |
| 실제 입력 도달성 | 줍기·이동·웅크리기는 입력에 연결. `NetPickup.request_throw_bait_for()`는 테스트/하네스가 직접 호출 | `project.godot`에 미끼 투척 액션이 없고 실제 플레이어가 미끼를 던질 수 없음 |
| 회색 상자 콘텐츠 배치 | `survival_demo.tscn`에는 붕대·돌·나무·모닥불 자리만 존재 | `raw_meat`, `bait`가 실제 판에 없어 출혈 외 냄새 선택과 미끼 선택을 손으로 시험할 수 없음 |
| 목표와 실패 | `LoopObjective`는 `risk_exposed && extraction 도달`이면 성공, 시간 만료만 실패 | 랩터 조사·추격·회피를 거치지 않아도 성공. 랩터가 플레이어와 겹쳐도 피해·포획·실패가 없어 무시 가능 |
| 플레이어 감각 피드백 | HUD에 바람 화살표, 최근 소리 방향, 랩터 추격 경보, 생존 단계가 존재 | 세션 남은 시간·목표 조건·성공/실패·보이는 탈출 지점·미끼 조작 안내 없음 |
| 소리 생산 경로 | 행동별 데이터와 반복 병합, 벽 감쇠, 원격 자세 권위 검증이 테스트됨 | `sense_loop_harness.gd`의 소리 단계는 실제 입력/`NoiseEmitter`가 아니라 `EventBus.noise_emitted` 직접 주입 |
| 냄새 생산 경로 | 출혈, 바닥/보유 날고기, 착지 미끼, 바람 이류와 권위 스냅샷이 구현됨 | 하네스 냄새 단계가 `EventBus.smell_emitted` 직접 주입. `Inventory._first_carried_smell_item()`은 첫 냄새 아이템 하나만 등록 |
| 랩터 역할 | 한 개체가 최근접 비보호 플레이어를 추격하고, 불·상실·재탐색을 처리 | 무리·고립 대상 우선·측면 포위·공격은 없음. W5에는 포획 실패만 필요하고 무리 AI는 중단 기준 뒤로 미룸 |
| 부상 부위 | `HealthComponent`가 전역 체력·출혈만 소유하고 붕대로 지혈 | 머리/몸통/팔/다리 구분과 부위별 효과 없음 |
| 인벤토리 | 8칸, 스택, 부분 획득, `total_weight()` 계산, 호스트 권위 획득·재접속 복원 | 설계의 16칸·무게 제한·장비 슬롯 없음. 무게는 계산만 하고 획득을 제한하지 않음 |
| 제작 | 전용 `scripts/crafting/`, `RecipeData`, 제작 RPC가 없음 | 모닥불 설치가 돌·나무를 직접 소비할 뿐 제작법 시스템은 없음 |
| 거점 설비 | 지정 자리에 스냅되는 모닥불 1종, 연료 60초, 네트워크 권위 구현 | 건조대·저장 바구니·침낭 등은 없음. 이번 블록에는 기존 모닥불만 재사용 |
| 세션 | 한 phase의 남은 초만 복제하며 날짜·낮/밤·날씨 없음 | 3일 세션 골격과 day 상태 복제·재접속 복원 없음 |
| 데이터 등록 | `GameData.ITEM_PATHS`에 5개 아이템 경로를 명시적으로 등록 | 디렉터리 스캔/manifest 없음. 현재 규모에서는 기능 장애가 아니며 이번 블록은 명시 목록 유지 |
| ENet 테스트 | 테스트별 고정 포트 `8911~8930`, CI는 단일 job에서 직렬 실행 | 같은 워크트리에서 여러 Godot 프로세스가 전체 GUT를 동시에 돌리면 포트 경합 가능 |
| 성능 증거 | macOS Apple M5 headless 감지 루프 기준선: frame p95 `6.944ms`, AI p95 `0.070ms`, scent p95 `0.053ms`, active cells max `13` | 로컬 회귀 증거일 뿐 Windows 최소 사양 판정이 아님. 기준선에는 100ms 초과 stall 1회도 기록되어 있어 출시 성능 통과로 해석 금지 |

## 3. 우선순위 원칙

1. W5 재미 관문 전에는 콘텐츠를 늘리지 않는다. 사람이 현재 단서를 읽지 못하면 랩터 수와 아이템 수를 늘려도 원인이 가려질 뿐이다.
2. 자동 테스트는 결정성과 회귀를 판정하고, 사람 플레이는 예측 가능성·공정성·재도전 의사를 판정한다. 둘 중 하나로 다른 하나를 대체하지 않는다.
3. 새 위험·제작·부상 결과는 처음부터 호스트가 확정한다. 클라이언트는 목표 좌표, recipe id, 치료 의도만 보낸다.
4. W6은 하나의 얇은 수직 절편만 만든다. 부상은 다리 열상 1종, 제작은 미끼 1종, 설비는 기존 모닥불 1종, 세션은 3일 시계 골격까지만이다.
5. 회색 상자 표시는 Godot 기본 도형·Label을 사용한다. 방향 에셋을 새로 만들지 않으므로 에셋 생성 정책 작업도 이번 블록에는 없다.

## 4. W3~4 이월 부채 채택/기각

| 이월 항목 | W5~6 결정 | 실제 근거와 재검토 조건 |
|---|---|---|
| `sense_loop_harness`의 EventBus 직접 주입 | **W5 채택** (`W5-T4`) | 현재 10/10은 소비자 경로만 증명한다. 실제 입력→`NoiseEmitter`/`SmellSource`→랩터→목표 판정으로 바꿔 가짜 완료를 막음 |
| 보유 냄새 강도 합산/우선순위 | **이번 블록 기각** | 현재 보유 냄새 원천은 `raw_meat` 한 종류뿐이고 `bait`는 착지 후에만 냄새를 낸다. 두 번째 보유 냄새 ItemData가 추가되거나 수량별 냄새 밸런스가 재미 테스트에서 필요해질 때 합산 규칙과 상한을 먼저 RED로 정의 |
| 신규 스폰 직후 피로 약 0.75/100 | **기각** | `SurvivalStats.reset_motion_baseline()`이 있고 관측된 값은 행동 단계·사망·네트워크 진행을 바꾸지 않음. 단계 경계나 스태미나 테스트가 실패할 때만 수정 |
| `NoiseEmitter` 자체 성능 샘플 | **별도 작업 기각** | 반복 병합·총 이벤트 수·AI/냄새 p95가 이미 관측됨. W5 recorder가 생산 이벤트 수를 추가 기록하고, 소리 처리 p95 0.5ms 예산 접근이 확인될 때 커스텀 모니터 추가 |
| `SurvivalStats`의 코드 `add_child` | **기각** | 실제 런타임 노드와 네트워크 테스트가 존재한다. 씬 편집 가시성만을 위해 `player.tscn` 충돌을 늘리지 않음 |
| 랩터 무리/고립 우선/측면 포위 | **W5 기각** | 현재 판은 랩터 1개체의 재미도 아직 사람에게 미검증. W5가 재미는 통과하지만 지나치게 쉽고 예측 정확도·성공률이 상한을 넘을 때 W7 후보로 재검토 |
| 수분/포만 행동 효과 | **이번 블록 기각** | W6 첫 절편의 부상·제작·3일 시계와 직접 연결되지 않음. 3일 압박 밸런스를 시작하는 W7 이후가 맞음 |
| `GameData` manifest/디렉터리 스캔 | **이번 블록 기각** | 현재 5 ItemData이며 W6 제작은 기존 `raw_meat`/`bait`를 재사용한다. 명시 목록은 누락·중복 검토가 쉽다. ItemData 10개 이상 또는 등록 누락 2회 재발 시 명시 manifest Resource를 먼저 검토하고, 무조건 디렉터리 스캔하지 않음 |
| 병렬 Godot ENet 포트 경합 | **실행 규칙 채택, 코드 변경 기각** | CI는 이미 한 job에서 직렬이다. 같은 워크트리 작업자는 비-ENet 대상 테스트만 병렬 실행하고 전체 GUT/ENet 하네스는 코디네이터가 wave 끝에 1회 직렬 실행. 이 규칙 아래 재발하면 동적 포트 할당을 별도 태스크로 승격 |

## 5. 제안 태스크

### W5-T1. 실제 입력으로 냄새 짐·미끼를 쓰는 회색 상자 판

- 목표: 디버그 전용 `sense_playtest.tscn`을 실행한 사람이 테스트 메서드 호출 없이 날고기/미끼를 줍고, 마지막 이동 방향으로 미끼를 던져 소리·냄새를 만들 수 있게 한다. 이 씬은 `main.tscn`을 기반으로 한 inherited scene이며 도달 가능한 `raw_meat`·`bait`만 덧붙이는 회색 상자 오버레이다. 평상시 `boot.gd → main.tscn` 경로와 `survival_demo.tscn`은 바꾸지 않는다. 따라서 상시 `raw_meat` 바닥 냄새는 디버그 판의 `SmellGrid`에만 들어가고 CI와 기존 `main.tscn` 소비 하네스에는 존재하지 않는다.
- 대상 파일: 수정 `project.godot`, `scripts/player/player.gd`, `tests/items/test_throwable_bait.gd`, `tests/survival/test_player_survival.gd`; 신규 `scenes/debug/sense_playtest.tscn`, `tests/items/test_sense_playtest_scene.gd`
- 의존성: 기존 `NetPickup.request_throw_bait_for()`, `ThrowableBait`, `Inventory`, `GameData`
- 테스트 전략(RED 먼저): 일반 `main.tscn`에는 `raw_meat`·`bait` 오버레이와 초기 `raw_meat` 냄새 발신이 없고 디버그 씬에만 두 아이템이 존재함을 먼저 고정한다. 이어 `throw_bait` 입력 전에는 미끼가 소비되지 않음, 마지막 유효 이동 방향·최대 투척 거리, 1개 소비, 호스트 확정, 소리 1회, 등록 냄새 원천 1개를 검증한다. GREEN 뒤 디버그 씬에서 키 입력으로 재현하고, Wave 1 종료 때 §7.1의 모든 `main.tscn` 소비 하네스를 재검증한다.
- 난이도: M

### W5-T2. 무시할 수 없는 목표·포획 실패·최소 세션 HUD

- 목표: 보이는 탈출 지점, 남은 시간, 현재 조건, 성공/실패를 표시한다. 성공은 `플레이어 기원 위험 노출 → 그 이후 랩터 조사/추격 관측 → 실제 회피 → 탈출 지점` 순서를 요구하고, 랩터가 설정된 포획 반경 안에 유예 시간 이상 머물면 회색 상자 세션을 실패시킨다. 포획은 전투 구현이 아니라 W5 재미 검증용 최소 결과다.
- 노출 판정: **월드 배경 냄새와 플레이어 기원 냄새를 구분하고 후자만 `risk_exposed`로 센다.** 플레이어의 출혈, `raw_meat` 획득·휴대, 호스트가 확정한 미끼 투척이 노출이다. `NetPickup`은 성공한 호스트 투척을 직접 신호로 알리고 `LoopObjective`가 이를 구독한다. 전역 `EventBus.smell_emitted`만 보고 출처 없이 노출시키지 않으므로, 디버그 판의 바닥 `raw_meat`가 먼저 방출하거나 다른 월드 냄새가 생겨도 목표 단계는 열리지 않는다. 랩터 상태 전환도 노출 이후의 것만 순서에 반영한다.
- 대상 파일: 수정 `scripts/session/loop_objective.gd`, `scripts/items/net_pickup.gd`, `scenes/main.tscn`, `scenes/ui/hud/hud.gd`, `scenes/ui/hud/hud.tscn`, `tests/session/test_loop_objective.gd`, `tests/survival/test_hud.gd`, `tests/creature/test_main_scene.gd`; 신규 없음
- 의존성: 기존 `Raptor.state_changed`, `SessionClock`, `SenseIndicatorModel`, `EventBus.bleeding_started`/`item_picked_up`, `NetPickup`, 불 회피 상태
- 테스트 전략(RED 먼저): 월드 `raw_meat`의 주기 발신만으로는 노출되지 않음, 플레이어 출혈·날고기 획득·호스트 확정 미끼 투척은 각각 노출됨, 노출 전 랩터 전환은 성공 순서에 재사용되지 않음, `risk_exposed` 후 바로 탈출해도 성공하지 않음, 조사/추격 뒤 FLEE 또는 관심 상실을 관측하고 탈출하면 성공, 짧은 근접은 허용하지만 포획 유예 초과는 실패, 결과 확정 뒤 시계 정지, HUD 시간·조건·결과 갱신, 탈출 표식이 벽 안이 아님을 먼저 고정한다.
- 난이도: M

### W5-T3. 재미 판정용 세션 recorder

- 목표: 디버그 전용 판에서만 소리/냄새 단서, 랩터 상태 전환, 웅크리기·미끼·모닥불 선택, 포획/탈출, 플레이어의 사전 예측 표식을 타임라인으로 기록한다. `project.godot`에 `predict_sound`(기본키 `1`, 의미 `소리 → INVESTIGATE`)와 `predict_smell`(기본키 `2`, 의미 `냄새 → INVESTIGATE`)을 추가하고 HUD에 두 조작과 현재 대기 표식을 표시한다. 플레이 중에는 메모리에만 쌓고 세션 종료 시 `user://`에 익명 JSON 1개를 쓴다.
- 예측 레코드: 세션 상대 단조 시각을 쓰며 필수 필드는 `prediction_id`, `channel(sound|smell)`, `predicted_next_state(INVESTIGATE)`, `prediction_at`, `clue_emitted_at`, `state_changed_at`, `valid`, `hit`, `invalid_reason`다. 채널별 미결 표식은 1개만 허용한다. 최초의 같은 채널 단서에 대해 `prediction_at < clue_emitted_at <= prediction_at + 5초`면 유효 예측이고, 그 단서 뒤 최초 랩터 전환이 `clue_emitted_at < state_changed_at <= clue_emitted_at + 5초`이며 예측 상태와 같을 때만 적중이다. 단서 뒤 입력은 이전 단서의 적중으로 소급하지 않고, 반응 전환이 없거나 다른 상태면 유효 표본의 오답으로 남긴다.
- 대상 파일: 신규 `scripts/debug/sense_playtest_recorder.gd`, `tests/senses/test_sense_playtest_recorder.gd`; 수정 `scenes/debug/sense_playtest.tscn`, `project.godot`, `scenes/ui/hud/hud.gd`, `scenes/ui/hud/hud.tscn`
- 의존성: W5-T1~T2, 기존 EventBus 신호와 `LoopObjective.outcome_changed`
- 테스트 전략(RED 먼저): 두 InputMap 액션과 HUD 어포던스, 채널별 미결 표식 1개, 위 부등식의 경계값, 단서보다 늦게 입력한 예측은 이전 단서 적중으로 계산하지 않음, 소리/냄새 채널 분리 집계, 의도적 회피 선택과 후속 상태 변화의 시간 창, 포획까지 경고 시간, 종료 전 파일 I/O 0회, 종료 JSON 필수 필드·스키마 버전을 먼저 작성한다. §6.2의 예측 표본·정확도는 이 레코드의 `valid`·`hit`만 집계한다.
- 난이도: M

### W5-T4. 생산자 경로 감지 루프 하네스

- 목표: 현재 `sense_loop_harness.gd`의 직접 `EventBus.noise_emitted/smell_emitted` 주입을 제거하고 W5-T1의 `sense_playtest.tscn`을 통해 실제 플레이어 입력/`NoiseEmitter`, 월드 `raw_meat`/`SmellSource`, 미끼 투척, 포획 실패, 목표 성공 경로를 사용한다. seed 4001~4010 계약은 유지한다.
- 대상 파일: 수정 `scripts/senses/sense_loop_harness.gd`; 신규 없음
- 의존성: W5-T1~T2
- 테스트 전략(RED 먼저): 결과 필드 `noise_producer`, `smell_producer`, `player_choice`, `objective_completed`를 먼저 필수화해 기존 직접 주입 하네스를 실패시킨다. GREEN은 각 seed가 네 필드와 기존 조사·상실·회피 필드를 모두 통과해야 exit 0이다.
- 난이도: M

### W5-T5. 10회 사람 플레이와 5주 말 중단 판정

- 목표: 자동 회귀와 사람의 재미를 분리해 기록하고 `통과 / 수치 조정 후 재시험 / 감지 시스템 재설계` 중 하나를 근거와 함께 확정한다.
- 대상 파일: 신규 `docs/technical/WEEK5_SENSE_FUN_GATE.md`, `docs/technical/BASELINE_W5_SENSE_PLAYTEST.json`; 수정 `scripts/debug/sense_playtest_recorder.gd`, `tests/senses/test_sense_playtest_recorder.gd`
- 의존성: W5-T3~T4, 아래 §6의 사전 확정된 지표
- 테스트 전략(RED 먼저): 유효 세션 10개 미만, 원시 로그 누락, 소리/냄새 표본 한쪽 누락, 계산식 불일치 시 gate validator가 실패하는 상태다. GREEN은 원시 세션 수와 집계값이 일치하고 필수 지표가 모두 판정 가능한 경우다. 체크박스나 사람이 쓴 PASS 문자열만으로 통과시키지 않는다.
- 난이도: S~M

### W6-T1. 16칸·무게 제한 인벤토리

- 목표: 설계서 5.8의 기본 16칸과 무게 제한을 적용한다. 슬롯 또는 무게 중 먼저 닿는 상한까지만 부분 획득하며, 호스트가 ItemData 무게로 다시 계산한다. 장비 슬롯은 만들지 않는다.
- 대상 파일: 수정 `scripts/inventory/inventory.gd`, `scenes/player/player.tscn`, `scenes/ui/hud/hud.gd`, `scenes/ui/hud/hud.tscn`, `tests/inventory/test_inventory.gd`, `tests/survival/test_hud.gd`; 신규 `tests/inventory/test_inventory_weight.gd`
- 의존성: W5 중단 기준 통과, 기존 `ItemData.weight`, `NetPickup` 부분 획득 불변식
- 테스트 전략(RED 먼저): 16칸, 무게 정확 경계, 초과 부분 획득, 0무게/비정상 무게 데이터 거부, 슬롯 여유가 있어도 무게 초과 거부, 제거 후 용량 복구, 획득 총합 보존을 먼저 작성한다.
- 난이도: M

### W6-T2. 신체 부위 첫 절편: 다리 열상과 붕대 치료

- 목표: 머리/몸통/팔/다리 식별자를 도입하되 활성 부상은 다리 열상 1종만 만든다. 다리 열상은 이동 효율을 낮추고 기존 출혈·피 냄새와 연결되며, 붕대 치료가 출혈과 열상을 함께 해소한다. 상태는 호스트 권위 스냅샷과 재접속에 보존한다. `InjuryComponent`는 `SurvivalStats`와 동일하게 `player.gd`에서 생성해 `add_child`하고 `player.tscn`은 편집하지 않으므로 W6-T1과 Wave 4 병렬 소유권을 유지한다.
- 대상 파일: 신규 `scripts/survival/injury_component.gd`, `tests/survival/test_injury_component.gd`; 수정 `scripts/survival/health_component.gd`, `scripts/survival/heal_target.gd`, `scripts/survival/survival_config.gd`, `data/survival/survival_config.tres`, `scripts/player/player.gd`, `scripts/survival/net_survival.gd`, `scripts/net/net_resync.gd`, `tests/survival/test_healing.gd`, `tests/survival/test_player_survival.gd`, `tests/survival/test_net_survival.gd`, `tests/net/test_net_resync.gd`
- 의존성: W5 중단 기준 통과, 기존 피해·지혈·냄새·치료 홀드·재접속 경로
- 테스트 전략(RED 먼저): 허용 부위 4개와 잘못된 값 거부, 다리 열상만 이동 배율 적용, 수치가 0이어도 즉사하지 않음, 지혈 전 피 냄새/지혈 후 정지, 클라이언트가 부위·효과를 확정할 수 없음, 치료 중 이탈/사망, 재접속 후 동일 부위·상태 복원을 먼저 작성한다.
- 난이도: L

### W6-T3. 퀵 제작 1종: 날고기 → 미끼

- 목표: `RecipeData`와 원자적 재료 소비/결과 지급의 최소 제작 도메인을 만든다. 첫 recipe는 기존 `raw_meat 1 → bait 1`만 사용하고, `data/recipes/craft_bait.tres`의 `RecipeData.result`는 새 아이템을 만들지 않고 기존 `data/items/bait.tres`를 참조한다. 플레이어는 퀵 제작 입력으로 요청하고, 클라이언트는 recipe id만 보내며 호스트가 재료·결과·인벤토리 여유를 검증한다. EventBus 신규 신호는 추가하지 않고 제작 결과는 `Crafting` 직접 신호와 기존 `Inventory.changed` 경로로 알린다.
- 대상 파일: 신규 `scripts/crafting/recipe_data.gd`, `scripts/crafting/crafting.gd`, `data/recipes/craft_bait.tres`, `tests/crafting/test_crafting.gd`, `tests/crafting/test_net_crafting.gd`; 수정 `scripts/core/game_data.gd`, `scripts/items/net_pickup.gd`, `scripts/player/player.gd`, `project.godot`, `tests/items/test_throwable_bait.gd`
- 의존성: W6-T1, 기존 `Inventory`, `RpcGuard`, `NetPickup`의 호스트 권위 item mutation 골격
- 테스트 전략(RED 먼저): 재료 부족 시 무변경, 결과 공간/무게 부족 시 무변경, 정확히 1회 소비·지급, 알 수 없는 recipe 거부, 클라이언트 수량·결과 주장 불가, 동시 요청 총합 보존, 제작한 미끼를 실제 투척 가능함을 먼저 작성한다.
- 난이도: M~L

### W6-T4. 3일 세션 시계 골격과 압축 통합 하네스

- 목표: `SessionClock`을 기본 10분 × 3일의 호스트 권위 day/time 모델로 확장하고 HUD·재접속에 반영한다. day/time 변화는 `SessionClock` 직접 신호로 노출하고 EventBus 신규 신호는 추가하지 않는다. 기존 모닥불을 이 절편의 유일한 거점 설비로 재사용한다. 날씨·일자별 사건·수면·새 설비는 추가하지 않는다. W6-T3 또는 T4에서 EventBus 신규 신호가 불가피하다고 RED가 증명하면 코디네이터가 Wave 4 종료 시 두 태스크 배포 전에 선반영하며, 병렬 작업자가 같은 파일을 각각 수정하지 않는다.
- 대상 파일: 신규 `scripts/session/three_day_slice_harness.gd`; 수정 `scripts/session/session_clock.gd`, `scripts/session/loop_objective.gd`, `scenes/main.tscn`, `scenes/ui/hud/hud.gd`, `scenes/ui/hud/hud.tscn`, `tests/session/test_session_clock.gd`, `tests/session/test_loop_objective.gd`, `tests/survival/test_hud.gd`, `.github/workflows/ci.yml`
- 의존성: W5 중단 기준 통과, W6-T1~T2의 상태 모델; W6-T3와 파일은 겹치지 않으므로 같은 wave 실행 가능
- 테스트 전략(RED 먼저): day 1→2→3 경계, day 3 종료 1회, 속도 배율에서도 같은 순서, 클라이언트 day 주장 불가, 재접속 day/time 복원, 압축 day에서 모닥불·부상·인벤토리 상태 유지, 최종 목표 성공/시간 초과 실패를 먼저 작성한다.
- 난이도: M

## 6. 5주 말 재미 중단 기준 판정

### 6.1 자동 관문과 사람 관문

자동 관문은 생산 경로가 깨지지 않았는지만 판정한다.

- GUT 전체 `0 failure`
- 생산자 경로 감지 하네스 seed 4001~4010 `10/10 PASS`
- 각 seed에서 실제 소리 생산, 실제 냄새 원천, 플레이어 회피 선택, 목표 성공 또는 포획 실패가 기록됨
- 감지 루프 기준 대비 p95 `+10%`면 경고, `+20%` 또는 절대 예산 초과면 차단

사람 관문은 최소 10세션으로 판정한다. 구현자 편향을 줄이기 위해 관련 코드를 작성하지 않은 플레이어의 세션을 4개 이상, 2인 세션을 4개 이상 포함한다. 정상 완주는 8~15분을 유효 범위로 보고, 조기 포획은 단서 기회가 2회 이상 있었을 때 유효 실패로 센다.

### 6.2 관측 지표와 제안 임계값

| 지표 | 계산 | 통과 제안값 | 실패가 뜻하는 것 |
|---|---|---:|---|
| 예측 표본 | W5-T3 식 `prediction_at < clue_emitted_at <= prediction_at + 5초`를 만족해 `valid=true`인 레코드 수 | 전체 30건 이상, 소리/냄새 각 10건 이상 | 표본 부족이면 재미 판정 보류 |
| 예측 정확도 | `hit=true`인 유효 예측 / `valid=true`인 예측. 적중은 단서 뒤 5초 내 최초 상태 전환이 `predicted_next_state`와 같은 경우뿐 | 전체 70% 이상, 소리·냄새 각 60% 이상 | 단서가 읽히지 않거나 AI 반응 규칙이 일관되지 않음 |
| 회피 선택 효율 | 웅크리기·미끼·모닥불 뒤 5초 안에 조사 목표 변경, 거리 증가, CHASE 이탈 중 하나 발생 | 전체 60% 이상, 세 선택 각각 성공 2회 이상 | 선택이 장식이거나 피드백이 늦음 |
| 공정 경고 | CHASE 시작부터 포획까지 시간과 경보 노출 기록 | 모든 포획에서 설정된 유예 시간 준수, 경보 누락 0건 | 피할 시간 없는 실패 |
| 원인 설명 | 세션 직후 `어떤 행동→어떤 단서→어떤 랩터 반응`을 플레이어가 설명 | 10세션 중 8세션 이상 | 실패 원인이 보이지 않음 |
| 난이도 대역 | 성공 세션 / 유효 세션 | 30~80% | 아래면 불공정/과도, 위면 긴장 부족 가능성 |
| 세션 길이 | 정상 완주 세션 중앙값 | 8~15분 | 너무 짧으면 선택 연쇄가 없고, 너무 길면 반복 노동 |
| 재미 | 세션 후 1~5점 `단서를 읽고 피하는 과정이 재미있었는가` | 중앙값 4 이상 | 핵심 약속 자체가 약함 |
| 재도전 의사 | `다른 시드로 한 번 더 하겠다` 예 | 10세션 중 7 이상 | 학습·변주 보상이 약함 |

### 6.3 결정 규칙

- **통과:** 자동 관문 전부 통과 + 예측 정확도 + 원인 설명 + 재미 + 재도전 의사 통과. W6 태스크를 시작한다.
- **수치 조정 후 재시험:** 재미·예측은 통과하지만 성공률 또는 세션 길이만 범위를 벗어난다. `CreatureData`, `NoiseProfile`, 냄새/포획 유예 데이터만 조정하고 5세션을 다시 돈다.
- **감지 시스템 재설계:** 예측 정확도, 원인 설명, 재미 중 하나가 수치 조정 1회 뒤에도 실패한다. 신규 공룡·무리 AI·W6 콘텐츠를 중단하고 단서 표현/AI 관심도/냄새 경사 중 실패 채널을 먼저 재설계한다.

## 7. 병렬 실행 wave와 파일 충돌

### 7.1 Wave 제안

| Wave | 병렬 태스크 | 시작 조건 | wave 종료 관문 |
|---:|---|---|---|
| 0 | 기준선 확인 | 브랜치 시작 | Godot import 1회, GUT 46/266/983/0, 감지 10/10 |
| 1 | W5-T1, W5-T2 | Wave 0 통과 | 각 담당 targeted GUT 후 코디네이터가 전체 GUT(메인 씬 성능 테스트 포함), `goal_scene_replay` x3, `two_player_harness`, `two_player_coop_harness`, `two_player_raptor_harness`, CI `two_player_goal_scene_harness` x5, 기존 `sense_loop_harness` 10시드를 직렬 재검증. 일반 `main.tscn`에 디버그 아이템/초기 `raw_meat` 발신이 없다는 격리 테스트도 필수 |
| 2 | W5-T3, W5-T4 | Wave 1 병합 | recorder 단위 테스트 + 생산 경로 10시드 |
| 3 | W5-T5 | Wave 2 통과 | §6 결정 기록. **실패 시 이후 wave 취소** |
| 4 | W6-T1, W6-T2 | W5 재미 관문 통과 | 인벤토리 총합·부상 권위·재접속 targeted GUT, 전체 GUT 직렬 |
| 5 | W6-T3, W6-T4 | Wave 4 통과 | 제작 동시성, 3일 압축 하네스, 전체 GUT·기존 하네스 직렬 |
| 6 | 통합 검증/리뷰 | Wave 5 통과 | 가짜 완료 스캔, 성능 회귀, 변경 파일 소유권 확인, W5~6 검증 리포트 |

같은 wave의 태스크는 아래 대상 파일 집합이 겹치지 않는다. Godot `.godot` import/cache와 ENet 포트는 파일 집합 밖의 공유 자원이므로 import와 전체 GUT/ENet 하네스는 코디네이터만 직렬 실행한다. 편집 파일과 별도로 §7.3의 공유 런타임 자원도 wave 종료 후 병합본에서 검증한다.

### 7.2 파일 충돌 매트릭스

`●`는 계획상 수정/신규 대상 파일이 하나 이상 겹친다는 뜻이다. 같은 wave에는 `●` 조합이 없다.

| 태스크 | W5-1 | W5-2 | W5-3 | W5-4 | W5-5 | W6-1 | W6-2 | W6-3 | W6-4 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| W5-1 | — |  | ● |  |  |  | ● | ● |  |
| W5-2 |  | — | ● |  |  | ● |  | ● | ● |
| W5-3 | ● | ● | — |  | ● | ● |  | ● | ● |
| W5-4 |  |  |  | — |  |  |  |  |  |
| W5-5 |  |  | ● |  | — |  |  |  |  |
| W6-1 |  | ● | ● |  |  | — |  |  | ● |
| W6-2 | ● |  |  |  |  |  | — | ● |  |
| W6-3 | ● | ● | ● |  |  |  | ● | — |  |
| W6-4 |  | ● | ● |  |  | ● |  |  | — |

재계산 기준은 위 각 태스크의 수정·신규 파일 전체다. 같은 wave 쌍 `W5-T1‖W5-T2`, `W5-T3‖W5-T4`, `W6-T1‖W6-T2`, `W6-T3‖W6-T4`는 모두 공집합이므로 새 same-wave 파일 충돌은 없다.

### 7.3 공유 런타임 자원

| 자원 | 관련 태스크/위험 | 격리·병합 검증 규칙 |
|---|---|---|
| `main.tscn` | W5-T1 디버그 판과 W5-T4 생산자 하네스의 간접 기반, W5-T2 목표/HUD 배선, 기존 E2E 소비자, W6-T4 시계 통합 | W5-T1은 별도 `sense_playtest.tscn`에서만 아이템을 추가해 평상시 main 런타임을 오염시키지 않는다. Wave 1 병합 뒤 §7.1의 모든 main 소비 하네스로 격리와 결정성을 확인한다. |
| `SmellGrid` | W5-T1 바닥/휴대/투척 냄새, W5-T2 노출 판정, W5-T3 기록, W5-T4 생산자 하네스 | 바닥 냄새는 디버그 씬에만 존재하고, `LoopObjective`는 출처 없는 전역 냄새를 노출로 세지 않는다. recorder와 생산자 하네스는 서로 다른 씬/프로세스에서 실행한 뒤 Wave 2 관문에서 함께 검증한다. |
| `EventBus` | W5-T2 기존 출혈·획득 신호, W5-T3 단서 기록, W5-T4 생산 경로, W6-T3/T4 신호 유혹 | W5는 기존 신호 계약을 유지하고 미끼 투척은 `NetPickup` 직접 신호를 쓴다. W6-T3/T4는 EventBus 신규 신호 금지이며 불가피할 때만 코디네이터가 Wave 4 종료 시 단일 선행 변경한다. |
| `InputMap` (`project.godot`) | W5-T1 `throw_bait`, W5-T3 `predict_sound`/`predict_smell`, W6-T3 퀵 제작 | 세 태스크는 각각 Wave 1/2/5라 편집 시점이 겹치지 않는다. 각 wave에서 기존 액션 보존과 신규 액션 중복 키를 targeted GUT로 확인한다. |

### 7.4 파일 소유권 요약

- W5-T1: 입력·플레이어·디버그 회색 상자 오버레이
- W5-T2: 목표·NetPickup 투척 신호·main·HUD
- W5-T3: recorder·예측 InputMap/HUD·디버그 오버레이 배선
- W5-T4: 기존 감지 하네스 단독
- W5-T5: recorder 집계·재미 gate 문서
- W6-T1: Inventory·player scene·HUD
- W6-T2: Injury/Health/Heal·Player script·NetSurvival/NetResync
- W6-T3: Crafting·GameData·NetPickup·Player script·입력
- W6-T4: SessionClock/LoopObjective·main·HUD·CI

## 8. 성능·보안·회귀 예방

### 네트워크 권위

- 포획, 부상 부위, 제작 결과, day/time, 목표 결과는 호스트만 확정한다.
- 제작 RPC는 recipe id만 받고 수량·재료·결과를 받지 않는다. 호스트의 `RecipeData`와 `Inventory`로 전부 다시 계산한다.
- 인벤토리 무게는 클라이언트 합계를 받지 않고 호스트의 ItemData로 계산한다.
- 부상 부위 enum 범위, day 범위, 유한 좌표, RPC 빈도·payload 상한을 기존 `RpcGuard` 관례로 검증한다.

### 성능

- recorder는 디버그 전용 `sense_playtest.tscn`에서만 활성화하고 플레이 도중 동기 파일 I/O를 하지 않는다.
- W6 인벤토리·제작·상태 p95 목표는 성능 문서의 합계 `0.5ms` 이하를 유지한다.
- day/time은 매 프레임 RPC로 보내지 않고 기존 호스트 스냅샷/재접속 시점에 맞춘다.
- 기존 `BASELINE_W3_4_SENSE_LOOP.json`은 개발기 회귀 기준으로만 비교한다. Windows 최소 사양 승인 근거로 승격하지 않는다.

### 가짜 완료 방지

- `main.tscn` 실제 배선, 실제 입력, 생산자 경로, 호스트 권위, 재접속을 각각 실행 가능한 테스트나 하네스로 남긴다.
- GUT의 파싱 누락 방지를 위해 CI의 `test_*.gd` 대조 관문을 유지한다.
- wave 종료마다 다음 스캔을 실행하고, 현재 허용된 `tests/net/test_rpc_guard.gd`의 추상 세션 stub `pass`와 `test_sense_loop_budget.gd`의 CPU spin loop `pass`만 근거를 기록해 예외 처리한다.

```sh
rg 'TODO|FIXME|HACK|pass$|assert_true\(true\)|assert_false\(false\)|# func test_|skip|pending' scripts tests
```

## 9. 이번 2주 블록에서 하지 않을 것

- 랩터 무리·측면 포위·두 번째 공룡: W5 재미 실패 원인을 가리므로 추가하지 않는다.
- 전투·무기·공격 애니메이션: W5 포획 실패 규칙이면 회피 재미 판정에 충분하다.
- 골절·감염·저체온·공황 전체: W6은 다리 열상 1종만 끝까지 연결한다.
- 제작 화면·20개 recipe: 퀵 제작 1종만 만든다.
- 새 거점 설비: 이미 네트워크 권위가 있는 모닥불을 재사용한다.
- 날씨·일자별 사건·수면·저장: 3일 시계 골격 뒤 W7 이후 수직 절편으로 남긴다.
- GameData 자동 스캔·새 추상 계층·새 의존성: 현재 규모와 이번 기능에 필요하지 않다.
- 완성 에셋: 기본 도형·텍스트 회색 상자로 판정하며, 임시 에셋을 완성물로 표시하지 않는다.

## 10. 개정 이력

- BLOCKER-1: W5-T3에 `predict_sound`/`predict_smell` InputMap·HUD 어포던스와 예측 레코드 스키마·단서 emit 대비 유효/적중식을 추가하고 §6.2 계산식과 통일했다.
- MAJOR-1: `raw_meat`·`bait`를 별도 `sense_playtest.tscn`에 격리하고 W5-T1 파일·테스트·Wave 1의 전체 main 소비 하네스 재검증 관문을 갱신했다.
- MAJOR-2: 월드 배경 냄새는 제외하고 출혈·날고기 휴대·호스트 확정 미끼 투척만 `LoopObjective` 노출로 세도록 W5-T2에 명문화했다.
- MINOR-1: W6-T2 `InjuryComponent`를 `SurvivalStats`와 같은 코드 `add_child` 방식으로 고정해 `player.tscn` 비편집과 Wave 4 병렬성을 보장했다.
- MINOR-2: W6-T3/T4의 EventBus 신규 신호를 금지하고 불가피한 경우 Wave 4 종료 시 코디네이터 단일 선행 변경으로 처리하도록 정했다.
- MINOR-3: 레시피를 `data/recipes/craft_bait.tres`로 바꾸고 `RecipeData.result`가 기존 `data/items/bait.tres`를 참조하도록 명시했다.

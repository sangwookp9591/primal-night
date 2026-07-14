# PRIMAL NIGHT W3~4 작업 범위 갭 분석 및 우선순위 제안

- 작성일: 2026-07-14 (Asia/Seoul)
- 범위: 분석 전용. 코드 수정·커밋 없음.
- 기준 문서: `docs/superpowers/specs/2026-07-13-primal-night-design.md`, `docs/technical/2026-07-13-performance-budget-and-regression-policy.md`, `docs/technical/2026-07-14-asset-generation-policy.md`
- 기준선: Godot 4.7 stable, GUT `34 scripts / 199 tests / 696 asserts / 실패 0`

## 1. 결론

3~4주차의 최단 경로는 **생존 수치 전체 구현이 아니라, 소리·냄새로 랩터를 예측하고 피하는 회색 상자 루프를 플레이 가능한 판으로 만드는 것**이다. 이미 있는 강점은 랩터 1종, 발소리 이벤트, 피 냄새 격자, 바람 이류, 불 회피, 2인 이동·피해·치료·모닥불·재접속 동기화다. 부족한 핵심은 플레이어가 위험을 읽는 표면, 냄새 원천 다양화, 바람/소리의 세션 변수화, 랩터의 조사-상실-재탐색 루프, 10~15분짜리 목표 세션이다.

3~4주차에서는 공룡 5종, 제작 전체, 완전한 7일 세션, 완성 에셋을 만들지 않는다. 5주 말 중단 기준은 "소리·냄새로 공룡을 예측하고 피하는 플레이"이므로, 태스크는 그 판정에 직접 기여하는 순서로 둔다.

## 2. 현재 구현 갭

| 설계 항목 | 현재 상태 | 갭 |
|---|---|---|
| 4.x 세션 구조 | `SessionService`, `LocalSessionService`, 재접속 120초 슬롯, 30초 아바타 잔류, 상태 재동기화 존재 | 날짜/시간/날씨/바람을 소유하는 `Session` 도메인 없음. 7일 구조는 아직 목표 아님이지만, W3~4 회색 상자에는 최소 10~15분 세션 타이머와 루프 성공/실패 판정이 필요 |
| 5.1 생존 수치 4종 | 체력, 스태미나만 존재. HUD 단계 표시 일부 존재 | 체온/수분/포만/피로 없음. 단, W3~4의 핵심 루프에는 4종 전체보다 피로 또는 체온 1개만 랩터 회피 의사결정에 연결하는 것이 우선 |
| 5.2 부상/치료 | 출혈, 지속 피해, 피 냄새, 붕대 지혈, 치료 중 이동 잠금, 네트워크 검증 존재 | 머리/몸통/팔/다리 부위 없음. 열상/골절/감염/저체온/공황 없음. W3~4에는 출혈-냄새-치료 연쇄만 충분하고, 골절/공황은 W5 이후가 맞음 |
| 5.3 소리 | `EventBus.noise_emitted`, 걷기/달리기 반경, 벽 감쇠, 랩터 마지막 위치 조사 존재 | 행동별 데이터 리소스 없음. 수풀/채집/투척/함정/총격/공룡 울음 없음. 플레이어가 소리 반경·방향을 읽는 디버그/피드백이 약함 |
| 5.4 냄새/바람 | `SmellGrid`, 바람 방향/세기, 감쇠, 활성 셀, 디버그 격자, 권위 스냅샷 존재 | 냄새 원천이 사실상 출혈 중심. 날고기/조리 음식/시체/피 묻은 장비/미끼 없음. 바람이 세션 날씨와 연결되지 않고 디버그 키 중심 |
| 5.5 공룡 생태계 | 랩터 1종. 상태는 배회/조사/추격/도주. 2인 대상 선택, 불 회피, 소리/냄새 조사 존재 | 5종 생태계 없음. 랩터도 고립 대상 우선/측면 포위/무리 행동은 없음. W3~4에는 1종만 유지하고, 생태계는 "먹이/소리/냄새 원천" 역할의 더미 오브젝트로 대체 |
| 5.6 전투/은신 | 불 회피, 이동 잠금, 디버그 부상. 무기·공격·은신 시스템은 없음 | 웅크리기, 수풀 엄폐, 냄새 세척, 미끼/투척, 서버 권한 명중 판정 없음. W3~4는 전투보다 회피이므로 웅크리기/수풀 소음 감소만 먼저 |

## 3. 우선순위 원칙

1. 랩터를 죽이는 재미가 아니라 **예측해서 피하는 재미**를 먼저 검증한다.
2. UI나 에셋보다 시스템 원인-결과를 먼저 만든다. 단, 플레이어가 원인을 읽을 최소 피드백은 필수다.
3. 네트워크 권위 경로는 이미 있으므로, 새 위험 판정은 처음부터 호스트가 소유한다.
4. 성능 문서 기준에 맞춰 소리/냄새는 이벤트와 저주기 격자로 유지한다. 매 프레임 전체 노드 검색이나 전체 격자 순회는 금지한다.
5. 에셋 정책상 3주차부터도 회색 상자 유지. 필요한 것은 최소 HUD/디버그 표시와 회색 상자 미끼·수풀·고기뿐이다.

## 4. 제안 태스크

### W3-T2. 회색 상자 감지 루프 세션 골격

- 목표: 10~15분짜리 "다치거나 고기를 들고 이동 → 바람/소리로 랩터 유인 → 수풀/불/우회로 회피 → 지정 지점 도달" 루프를 세션 단위로 판정한다.
- 대상 파일: 신규 `scripts/session/session_clock.gd`, `scripts/session/loop_objective.gd`, `tests/session/test_loop_objective.gd`; 수정 `scenes/main.tscn`, `scripts/net/net_resync.gd`(필요 시 스냅샷에 최소 세션 상태 추가)
- 의존성: 기존 `EventBus`, `NetMovement`, `NetResync`, `Raptor`, `SmellGrid`
- 테스트 전략: RED로 타이머 만료 실패, 목표 지점 도달 성공, 재접속 후 목표 상태 복원 실패를 먼저 작성. GREEN은 날짜 7일 구현 없이 초 단위 `phase_time`만 둔다.
- 난이도: M

### W3-T3. 행동별 소리 데이터와 발신 API

- 목표: 걷기/달리기 외에 수풀 통과, 채집, 아이템 던지기, 모닥불 설치, 부상 신음을 `NoiseProfile` 데이터로 분리하고 랩터가 마지막 들은 위치만 조사하도록 유지한다.
- 대상 파일: 신규 `scripts/senses/noise_profile.gd`, `scripts/senses/noise_emitter.gd`, `tests/senses/test_noise_emitter.gd`; 수정 `scripts/player/player.gd`, `scripts/props/campfire_site.gd`, `scripts/items/world_item.gd` 또는 해당 상호작용 지점
- 의존성: `EventBus.noise_emitted`, `Raptor._on_noise_emitted`
- 테스트 전략: RED로 "채집 소리 반경 안 랩터 조사", "벽 감쇠", "source 이동 후에도 조사 위치 고정", "동일 위치 반복 소리 병합"을 검증. 기존 `test_raptor_hearing.gd`를 깨지 않게 유지.
- 난이도: M

### W3-T4. 냄새 원천 확장: 고기/미끼/피 묻은 장비

- 목표: 출혈 외 냄새 원천을 등록/해제 방식으로 추가한다. 첫 회색 상자 대상은 `raw_meat` 또는 `bait` 1종이면 충분하다.
- 대상 파일: 신규 `scripts/senses/smell_source.gd`, `tests/senses/test_smell_source.gd`; 수정 `scripts/senses/smell_grid.gd`, `scripts/items/world_item.gd`, `scripts/inventory/inventory.gd`, `scripts/net/net_resync.gd`(보유 냄새 상태가 필요할 때만)
- 의존성: `SmellGrid`, `Inventory`, `NetPickup`
- 테스트 전략: RED로 "바닥 고기가 주기적으로 냄새 생성", "집어 들면 바닥 냄새 원천 해제", "플레이어가 들고 있으면 플레이어 위치에서 냄새 생성", "권위만 발신"을 작성.
- 난이도: M

### W3-T5. 바람/위험 피드백 최소 HUD

- 목표: 숫자 격자 대신 플레이어가 읽을 수 있는 바람 화살표, 최근 큰 소리 방향, 랩터 경계 단계 표시를 제공한다. 디버그 표시와 플레이 HUD를 분리한다.
- 대상 파일: 신규 또는 수정 `scenes/ui/hud/hud.gd`, `tests/survival/test_hud.gd`, `tests/senses/test_debug_visuals.gd`; 필요 시 신규 `scripts/senses/sense_indicator_model.gd`
- 의존성: `SmellGrid.wind_direction`, `EventBus.noise_emitted`, `Raptor.state_changed`
- 테스트 전략: RED로 바람 방향 변경 시 HUD 모델 갱신, 음소거 사용자용 소리 방향 텍스트/아이콘 상태 갱신, 랩터 추격 진입 시 경고 표시를 검증. 렌더 픽셀 검증은 아직 과함.
- 난이도: S~M

### W3-T6. 랩터 조사 품질 개선: 상실/재탐색/관심도

- 목표: 랩터가 소리나 냄새를 듣고 정확 좌표로 순간 확신하지 않고, 조사 지점 주변을 짧게 훑은 뒤 상실하거나 재탐색한다.
- 대상 파일: 수정 `scripts/creature/raptor.gd`, `scripts/creature/creature_data.gd`, `tests/creature/test_raptor_states.gd`, `tests/creature/test_raptor_hearing.gd`; 필요 시 신규 `tests/creature/test_raptor_search.gd`
- 의존성: W3-T3 소리 데이터, W3-T4 냄새 원천
- 테스트 전략: RED로 "조사 도착 후 즉시 배회가 아니라 N회 탐색", "소리보다 시야 우선", "새 냄새가 강하면 재탐색", "플레이어 실시간 좌표 추적 금지"를 검증.
- 난이도: M

### W4-T1. 은신 최소 구현: 웅크리기와 수풀 소음 감소

- 목표: 전투 없이 회피 선택지를 만든다. 웅크리면 속도/소음이 감소하고, 수풀 안에서는 달리면 큰 소리·웅크리면 작은 소리가 난다.
- 대상 파일: 수정 `scripts/player/player.gd`, `scripts/player/player_config.gd`, `tests/survival/test_player_survival.gd`; 신규 `scripts/world/stealth_zone.gd`, `tests/senses/test_stealth_noise.gd`
- 의존성: W3-T3 `NoiseProfile`
- 테스트 전략: RED로 "웅크리기 속도 감소", "소리 반경 감소", "수풀 달리기 소리 증가", "랩터 조사 전환 차이"를 검증.
- 난이도: M

### W4-T2. 미끼/던지기 회피 도구

- 목표: 플레이어가 랩터를 피하기 위해 소리 또는 냄새 원천을 의도적으로 다른 곳에 만들 수 있게 한다. 무기 전투 대신 미끼 1종만 만든다.
- 대상 파일: 신규 `scripts/items/throwable_bait.gd`, `tests/items/test_throwable_bait.gd`; 수정 `scripts/items/net_pickup.gd`, `scripts/inventory/inventory.gd`, `scripts/core/game_data.gd`, `data/items/*.tres`
- 의존성: W3-T3, W3-T4, 기존 `NetPickup`
- 테스트 전략: RED로 "호스트가 투척 거리 검증", "투척 위치에 소리/냄새 생성", "인벤토리 1개 소비", "클라이언트 수량 변조 거부"를 검증.
- 난이도: M~L

### W4-T3. 생존 수치 4종의 최소 모델

- 목표: 설계서 5.1의 체온/수분/포만/피로를 데이터와 HUD 상태 단계로 넣되, 3~4주차 루프에는 피로와 체온만 실제 행동에 약하게 연결한다.
- 대상 파일: 신규 `scripts/survival/survival_stats.gd`, `tests/survival/test_survival_stats.gd`; 수정 `scripts/survival/survival_config.gd`, `scripts/player/player.gd`, `scenes/ui/hud/hud.gd`, `scripts/survival/net_survival.gd`
- 의존성: W3-T2 세션 시간, 기존 `StaminaComponent`
- 테스트 전략: RED로 "수치 저하가 즉사하지 않음", "피로가 스태미나 회복/달리기 효율에 영향", "체온이 모닥불 근처에서 회복", "스냅샷 복제"를 검증.
- 난이도: L
- 비고: 이 태스크는 5주차 중단 기준에는 간접 기여다. 시간이 부족하면 W5 초입으로 미룬다.

### W4-T4. 회색 상자 플레이 하네스 10회

- 목표: W3~4의 완료 판정을 사람 감상에만 두지 않고, 고정 시드 10개로 "예측 가능한 위기와 회피 성공/실패"를 자동 확인한다.
- 대상 파일: 신규 `scripts/senses/sense_loop_harness.gd`, `tests/creature/test_sense_loop_contract.gd`; 수정 `.github/workflows/ci.yml`은 코디네이터 승인 시
- 의존성: W3-T2~W4-T2
- 테스트 전략: GUT 단위 테스트와 별도로 headless 하네스 실행. 각 seed에서 최소 1회 소리 조사, 1회 냄새 조사, 1회 랩터 상실, 1회 회피 성공을 로그로 판정한다.
- 난이도: M

### W4-T5. 성능·네트워크 예산 게이트 보강

- 목표: 소리/냄새/랩터 루프가 성능 문서의 CPU 예산을 넘지 않는지 초기부터 막는다.
- 대상 파일: 수정 `scripts/core/perf_monitor.gd`, `tools/capture_frame_baseline.gd`, `tests/perf/*`; 신규 `docs/technical/BASELINE_W3_4_SENSE_LOOP.*`
- 의존성: W4-T4
- 테스트 전략: RED로 "냄새 활성 셀 상한", "소리 이벤트 반복 병합", "랩터 AI 평균 샘플 존재", "하네스 p95가 기준선 대비 악화 시 실패"를 검증. 정확한 저사양 PC 기준은 아직 아니므로 로컬 회귀 게이트로 둔다.
- 난이도: M

## 5. 권장 순서

| 순위 | 태스크 | 이유 |
|---:|---|---|
| 1 | W3-T2 | 세션 판정이 없으면 이후 기능이 재미 검증이 아니라 단위 기능 나열이 된다 |
| 2 | W3-T3 | 소리가 랩터 예측 플레이의 절반이다. 데이터화가 먼저여야 수풀/미끼가 얹힌다 |
| 3 | W3-T4 | 냄새 원천이 출혈뿐이면 플레이어 선택지가 "다치기"밖에 없다 |
| 4 | W3-T5 | 플레이어가 바람/소리/위험을 못 읽으면 시스템이 작동해도 불공정하게 느낀다 |
| 5 | W3-T6 | 랩터가 더 동물처럼 보이게 만드는 최소 AI 품질 개선 |
| 6 | W4-T1 | 은신 선택지. 전투보다 회피 루프에 직접 기여 |
| 7 | W4-T2 | 미끼는 위험을 능동적으로 조작하는 핵심 도구 |
| 8 | W4-T4 | 5주차 중단 기준 판정용 자동 증거 |
| 9 | W4-T5 | 기능이 늘어난 뒤 성능 회귀를 묶는다 |
| 10 | W4-T3 | 설계서 갭은 크지만 W3~4 핵심 루프에는 후순위. 단, W5 진입 전에는 착수 필요 |

## 6. 잠재 장애 요소와 기술 부채

### 네트워크 동기화

- 새 소리/냄새/미끼/은신 판정은 모두 호스트 권위여야 한다. 클라이언트가 "나는 조용했다", "미끼를 던졌다", "피 냄새가 없다"를 직접 확정하면 W2에서 막은 변조 경로가 다시 열린다.
- `NetResync`는 현재 인벤토리/체력/출혈/위치 중심이다. W3~4에서 보유 냄새 원천, 미끼 투척 상태, 세션 목표 상태가 생기면 재접속 스냅샷에 포함해야 한다.
- 현재 위치 스냅샷은 8명 상한 배열을 쓰지만 출시 목표는 2명이다. 3~4주차에는 늘리지 않는다.

### 성능 예산

- 냄새 격자는 활성 셀만 갱신하고 4Hz라 방향은 맞다. 단, 냄새 원천이 늘면 원천 목록 등록/해제 방식이어야 하며 매 틱 월드 아이템 전체 검색은 금지한다.
- 랩터는 `ai_tick_interval` 주기로 그룹 조회를 한다. 랩터 1종/소수 개체에서는 충분하지만, W4 하네스에서 랩터 수를 늘릴 경우 공간 해시 전환이 필요할 수 있다.
- 소리는 물리 오브젝트가 아니라 이벤트 구조체로 유지해야 한다. 반복 발소리/수풀 소리는 짧은 시간 병합하지 않으면 랩터 AI와 디버그 표시를 불필요하게 흔든다.
- 디버그 시각화는 개발 빌드 전용이어야 하며, 성능 측정 중 오버레이 문자열 조립이 측정을 오염시키지 않게 꺼진 상태를 기준선으로 둔다.

### 설계 부채

- `SurvivalConfig`가 체력/스태미나/출혈/치료/네트워크 상수를 모두 가진다. W4-T3에서 4종 생존 수치를 추가할 때 무작정 더 붙이면 커진다. 단, 지금 분리 리팩터링은 이르며 새 `SurvivalStats` 리소스가 필요해질 때만 나눈다.
- `GameData.ITEM_PATHS`는 3개 아이템만 하드코딩한다. W4-T2에서 미끼가 추가되면 최소 1개 항목 추가로 충분하지만, 제작법까지 들어오는 W5 이후에는 데이터 디렉터리 스캔 또는 명시 manifest를 검토한다.
- 랩터 상태는 현재 enum 4개로 단순하다. W3~4에는 충분하다. 무리 포위/섭식/휴식은 5주차 중단 기준 통과 전까지 추가하지 않는다.

### 가짜 완료 방지

- 완료 판정은 주석, TODO 제거, 디버그 원 표시가 아니라 실제 상태 변화와 하네스 로그여야 한다.
- 각 비자명 태스크는 RED→GREEN 증거를 남긴다. 최소 단위는 GUT 실패 테스트 1개와 성공 로그다.
- `rg 'TODO|FIXME|HACK|pass$|assert_true(true)|assert_false(false)|# func test_|skip|pending' scripts tests`를 태스크 종료마다 실행한다. 현재 `tests/net/test_rpc_guard.gd`의 `pass`는 세션 스텁 메서드이며 가짜 완료는 아니다.

## 7. 이번 범위에서 하지 않을 것

- 공룡 5종 전체 구현: W3~4에는 랩터 1종과 더미 냄새/소리 원천으로 충분하다.
- 전투 전체: 무기/피격박스/서버 명중 판정은 5.6 갭이지만, 5주차 중단 기준에는 은신/미끼가 먼저다.
- 7일 탈출 세션: W3~4는 10~15분 회색 상자 루프까지만.
- 완성 에셋: 에셋 정책에 따라 회색 상자와 최소 HUD만 사용한다.

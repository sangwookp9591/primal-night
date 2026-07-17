# PRIMAL NIGHT W5~6 작업 범위 갭 분석 및 우선순위 제안

- 작성일: 2026-07-17 (Asia/Seoul)
- 범위: 분석·계획 전용. 코드 수정·커밋 없음.
- 기준 문서: `docs/design/GAME_SCENARIO_WORLD_TILEMAP.md`(설계 정본), `docs/design/ACTION_SYSTEM_DESIGN.md`, `docs/technical/WEEK3_4_PLAN.md`, `docs/technical/WEEK3_4_VERIFICATION.md`, `docs/technical/W5_CRAFTING_MVP_VERIFICATION.md`, `docs/technical/2026-07-13-performance-budget-and-regression-policy.md`, `docs/technical/2026-07-14-asset-generation-policy.md`
- 기준선: Godot 4.7.1 stable, 커밋 `e907712`, GUT `61 scripts / 342 tests / 1385 asserts / 실패 0`, sense loop harness seed 4001~4010 `10/10 PASS`
- 정본 로드맵 대조: 설계서 §23의 `W5~6` 행(인벤토리·부상·퀵 제작·3일 시계)은 이미 **완료/검증 중**이다. 이 문서는 그 행의 잔여분(인벤토리 **화면**)과 5주차 중단 기준 통과로 해금된 범위를 묶어 **다음 마일스톤**을 정의한다. 정본 §23 기준 다음 행인 `W7~8`(타일·공간 수직 조각)에는 진입하지 않는다.

## 1. 결론

W5~6의 최단 경로는 **아이템을 더 늘리는 것이 아니라, 사체 해체로 자원을 얻는 대가가 곧 피 냄새와 소음이 되는 위험·보상 루프를 판정 가능한 판으로 만드는 것**이다.

다음 판정 기준은 한 문장이다.

> **사체를 해체해 자원을 얻고, 그 대가로 생긴 피 냄새와 소음을 감수하며 철수 시점을 고르는 플레이.**

이 문장을 고른 이유는 현재 구현의 가장 큰 자기모순이 여기 있기 때문이다. W5에서 만든 원시 제작 MVP는 **뼈 긁개**를 산출하는데, 뼈 긁개의 정의는 정본 §14.2에서 `해체 도구 / 사체 해체 시간 25% 감소`다. 그런데 저장소에는 해체할 사체가 없고, 재료인 `bone`은 `scenes/props/survival_demo.tscn`에 손으로 놓인 픽업 하나가 유일한 출처다(`survival_demo.tscn:43-45`). 즉 지금 제작 체인은 **쓸 곳이 없는 도구를, 나올 곳이 없는 재료로** 만들고 있다. 해체 루프를 넣으면 이 고리가 닫힌다. 해체 → 뼈·힘줄 → 뼈 긁개 → 더 빠른 다음 해체이고, 산출된 날고기는 포만을 회복시켜 위험을 감수할 이유가 된다.

이미 있는 강점은 그대로 재사용한다. `ActionController`/`TimedAction`의 홀드·취소·소음, 등록형 `SmellSource`와 `SmellGrid`의 바람 이류, `NoiseEmitter`의 병합·벽 감쇠, `NetPickup`/`NetCrafting`의 호스트 권위 지급 패턴이 전부 있다. 정본 §14.4가 요구하는 것도 정확히 "새 냄새 시뮬레이터나 미니게임을 만들지 말고 기존 시스템을 연결하라"다. 부족한 핵심은 사체 자체, 산출 확정(`yield_mask`), 수분·포만의 실제 효과, 그리고 무게·슬롯 압박을 읽을 표면이다.

W5~6에서는 랩터 사망·전투, 두 번째 공룡, 7일 세션, 청크 스트리밍, 완성 에셋을 만들지 않는다. 근거는 §7에 둔다.

## 2. 현재 구현 갭

| 설계 항목 | 현재 상태 | 갭 |
|---|---|---|
| 14.4 사체 해체 위험·보상 루프 | **없음.** 사체/시체 노드, 해체 행동, `yield_mask` 전부 부재. `bone`은 데모 씬 손배치 픽업이 유일 출처 | 정본 §22.2의 "반드시 포함"이다. 해체 홀드, 25% 구간 산출 확정, 절단 소음 240px, 단계별 피 냄새(신선 80/일부 55/골격 0)가 없다. 기존 `ActionController`+`NoiseEmitter`+`SmellSource` 연결로 만들 수 있고 새 시뮬레이터는 필요 없다 |
| 13 생존 수치 — 수분·포만 | 4종 모두 시뮬레이션·HUD 단계 표시·재접속 복제까지 존재. 그러나 **행동 효과는 피로 하나뿐** (`survival_stats.gd:107` → `player.gd:87` → `stamina_component.gd:27,34`) | 수분·포만은 감소만 하고 아무것도 바꾸지 않는다(`survival_stats.gd:10-13`이 자인). 체온도 모닥불이 *입력*일 뿐 출력이 없다. 회복 수단(섭취)도 없어 게이지가 편도다. 정본 §13은 "0이어도 즉사 없음, 스태미나 회복과 자연 체력 회복이 먼저 감소"를 요구 |
| 14.2 자원 34개 | 12개 등록(`stone/wood/fiber/bone/bandage/raw_meat/bait/smartphone/stone_knife/torch/bone_scraper/noise_lure`). 디렉터리 자동 스캔 완료 | 해체 산출인 `sinew`(힘줄)·`dinosaur_hide`(가죽) 없음. 운반 흔적 냄새(가죽 30, 힘줄 20) 규칙 미적용 |
| 14.3 핵심 제작 18개 | 레시피 5종(`bait/stone_knife/torch/bone_scraper/noise_lure`), 지식 발견·관찰문 저장 완료 | `craft_bone_scraper` 재료가 현재 `{bone:1, fiber:1}`로 정본 §14.3의 `공룡 뼈 2+힘줄 1`과 어긋난다. 힘줄이 없어서 생긴 임시 조합이며 해체 루프가 들어오면 정본으로 맞출 수 있다 |
| 15.1 랩터 AI | 4상태(`WANDER/INVESTIGATE/CHASE/FLEE`), 조사 훑기 2회, 관심도, 불 회피, 벽 감쇠. `main.tscn`에 **1마리** | 무리·측면 포위·고립 대상 우선 없음. 대상 선택은 `_perceive_players()`의 최근접 비보호 플레이어 하나뿐이며(`raptor.gd:249-251`) 개체 간 조율 코드가 전혀 없다. 5주차 중단 기준 통과로 해금된 범위(`WEEK3_4_VERIFICATION.md` §7) |
| 13/22.1 인벤토리 표면 | 16칸+무게 제한·호스트 권위 확정은 완료. HUD에 텍스트 슬롯 라벨 격자 존재 | **전체 화면 인벤토리 없음.** 무게·슬롯 압박을 읽을 수 없다. 정본 §14.4가 "한 사체 완전 해체 = 인벤토리 3~6칸"을 결정의 축으로 두는데, 그 축이 보이지 않는다 |
| 14.3 제작 지식 노트 | 발견 상태·관찰문 32개 저장, 호스트 권위, 재접속 복원 완료 | 열람 화면 없음. HUD `KnowledgeNotice` 한 줄이 **새 관찰문마다 덮어쓰기**(`hud.gd:235-237`)라 과거 관찰을 다시 읽을 방법이 없다. 정본은 노트를 "다음 판단에 쓸 관찰"로 정의하므로 다시 읽지 못하면 기능이 반만 있는 셈 |
| 18.1/22.1 세션 시간 | 3일 압축 시계(낮 420+황혼 60+밤 120초 × 3일 = 30분), 위상 전환·재접속 복원 완료 | MVP 목표는 7일×10분 = 70~90분. 다만 4~7일 구간은 정본 §18.1에서 대이동·화산재·분화와 부품 B/C를 요구하며 그 콘텐츠는 W7~8 이후다. §7에서 3일 유지 근거를 명시 |
| 19 영구 월드 상태 | 재접속 스냅샷(인벤토리·체력·출혈·부위·생존수치·위치·지식)만 존재 | 사체 `yield_mask`는 재접속·동시 해체에서 중복 지급을 막아야 하므로 스냅샷 대상이다. 디스크 저장·마이그레이션은 정본 §22.4 기준 W14 관문이므로 이번엔 세션 내 메모리 권위까지만 |

## 3. 우선순위 원칙

1. **아이템 수가 아니라 결정의 수를 늘린다.** 해체는 "고기·뼈·힘줄 중 무엇을, 몇 칸까지, 언제까지"라는 결정을 만든다. 산출물 종류를 늘리는 것 자체는 목표가 아니다.
2. **보상에는 반드시 감각 대가를 붙인다.** 정본 §14.4의 핵심은 산출이 아니라 산출하는 동안 20~40초 노출되고 피 냄새가 조사 목적지를 만든다는 것이다. 대가 없는 해체는 그냥 상자 열기다.
3. **새 시뮬레이터를 만들지 않는다.** 해체 소음은 `NoiseEmitter` 새 프로필, 피 냄새는 등록형 `SmellSource`, 홀드는 `ActionController`, 지급은 `NetPickup` 패턴이다. 정본 §14.4·§15.4가 명시적으로 요구하는 제약이다.
4. **새 위험 판정은 처음부터 호스트가 소유한다.** 클라이언트가 "조용히 해체했다", "이 bit는 아직 안 받았다"를 확정하면 W2에서 막은 변조 경로가 다시 열린다.
5. **회색 상자 유지.** 사체는 회색 상자 실루엣과 단계 색으로 충분하다. 에셋 정책상 완성 에셋은 범위 밖이다.
6. **실기 플레이 검증을 태스크 완료 조건에 넣는다.** W5에서 자동 테스트가 놓치고 실기가 잡아낸 것이 2건이었다(재료 스폰 없어 제작 체인 플레이 불가, `cycle_target` 오바인딩). 해체는 홀드·거리·중단이 얽혀 같은 종류의 구멍이 나기 쉽다.

## 4. 제안 태스크

### W5-T1. 사체 노드와 해체 홀드 골격

- 목표: 월드에 시드 배치된 사체를 도구를 들고 홀드해 해체하는 행동을 만든다. 맨손 불가, 돌칼 8초, 뼈 긁개 6초, 진행은 사체에 저장한다.
- 대상 파일: 신규 `scripts/world/carcass.gd`, `scripts/world/carcass_profile.gd`, `data/creatures/carcass_raptor.tres`, `tests/world/test_carcass.gd`; 수정 `scenes/props/survival_demo.tscn`(사체 1구 배치)
- 의존성: 기존 `ActionController`/`TimedAction`, `Interactor`의 interactable 덕 타이핑 계약(`can_interact/get_hold_seconds/get_prompt/interact/on_hold_started/on_hold_ended`)
- 테스트 전략: RED로 "맨손이면 `can_interact` 거부", "돌칼 8초·뼈 긁개 6초", "거리 72px 초과 시 중단", "중단해도 진행률이 사체에 남고 재개된다", "완전 해체 후 골격 상태로 더 이상 산출 없음"을 작성. 기존 `test_interactor_target_cycle`·`test_interactor_prompt_cache`를 깨지 않게 유지.
- 난이도: M

### W5-T2. 해체 산출 호스트 권위 확정 (`yield_mask`)

- 목표: 25% 구간마다 호스트가 산출 슬롯을 **한 번만** 확정한다. 재접속·동시 해체에서 같은 bit를 두 번 지급하지 않는다.
- 대상 파일: 신규 `scripts/world/net_butcher.gd`, `tests/world/test_net_butcher.gd`; 수정 `scripts/world/carcass.gd`, `scripts/net/net_resync.gd`(사체 `yield_mask` 스냅샷 추가)
- 의존성: W5-T1, W5-T4(산출 아이템 id 존재), 기존 `NetPickup`·`NetCrafting` 권위 패턴
- 테스트 전략: RED로 "25/50/75/100%마다 bit 1회만 설정", "같은 bit 재지급 거부", "클라이언트가 임의 `yield_mask` RPC를 보내면 거부", "인벤토리 만석이면 지급 실패해도 bit를 소모하지 않는다", "재접속 후 이미 받은 bit가 복원된다", "두 플레이어가 같은 사체를 동시 해체해도 총 산출이 상한을 넘지 않는다"를 작성.
- 난이도: M~L
- 비고: 정본 §14.4의 "재접속·동시 해체에서 같은 bit 두 번 지급 금지"가 이 태스크의 존재 이유다. 만석 처리는 bit 소모와 분리해야 산출이 조용히 증발하지 않는다.

### W5-T3. 해체 감각 비용: 절단 소음과 단계별 피 냄새

- 목표: 해체의 대가를 만든다. 구간 완료마다 240px 소음, 사체 단계별 피 냄새(신선 80 / 일부 해체 55 / 골격 0)를 등록형 원천으로 발신한다.
- 대상 파일: 신규 `data/senses/noise_butcher.tres`, `tests/senses/test_carcass_senses.gd`; 수정 `scripts/world/carcass.gd`
- 의존성: W5-T1, 기존 `NoiseEmitter`(병합·벽 감쇠), `SmellSource`/`SmellGrid`(등록형, 바람 이류, 0.85 감쇠)
- 테스트 전략: RED로 "구간 완료마다 240px 소음 1회", "0.5초 안 반복 소음 병합", "사체 단계가 내려가면 냄새 강도가 80→55→0", "권위만 발신(클라이언트 격자는 자체 시뮬레이션 금지)", "해체 소음 위치로 랩터가 조사 전환"을 작성.
- 난이도: M
- 비고: 판정 문장의 "피 냄새와 소음" 절반이 여기다. T2(보상)보다 이걸 먼저 빼면 안 된다.

### W5-T4. 해체 산출 아이템과 뼈 제작 정본화

- 목표: `sinew`(힘줄)를 추가하고 `craft_bone_scraper` 재료를 정본 §14.3의 `공룡 뼈 2+힘줄 1`로 맞춘다. 운반 흔적 냄새(힘줄 20)를 아이템 데이터로 넣는다.
- 대상 파일: 신규 `data/items/sinew.tres`; 수정 `data/recipes/craft_bone_scraper.tres`, `tests/crafting/test_primitive_recipes.gd`, `scenes/props/survival_demo.tscn`(손배치 `bone` 축소 또는 제거)
- 의존성: 없음(선행 없이 착수 가능). `GameData` 디렉터리 스캔이 이미 완료라 `.tres` 추가만으로 등록된다
- 테스트 전략: RED로 "`sinew` 자동 등록", "`craft_bone_scraper` 재료가 뼈 2+힘줄 1", "힘줄 보유 시 냄새 원천 강도 20", "기존 보유 냄새 합산 규칙(최댓값+가산 0.5, 상한 3배)과 함께 동작"을 작성. 재료 변경이 `test_primitive_recipes.gd`의 기대값과 데모 씬 제작 체인을 깨므로 함께 갱신.
- 난이도: S~M
- 비고: **T2보다 먼저 끝나야 한다.** T2가 지급할 아이템 id가 존재해야 하기 때문이다. 작아서 레인 B가 먼저 처리하고 넘긴다.

### W5-T5. 수분·포만 행동 효과 연결

- 목표: 감소만 하던 수분·포만에 실제 효과를 준다. 정본 §13대로 **0이어도 즉사하지 않고**, 스태미나 회복과 자연 체력 회복이 먼저 줄어든다.
- 대상 파일: 수정 `scripts/survival/survival_stats.gd`, `scripts/survival/survival_config.gd`, `scripts/player/player.gd`, `scripts/survival/stamina_component.gd`, `tests/survival/test_survival_stats.gd`
- 의존성: 없음(선행 없이 착수 가능). 기존 피로→스태미나 배선(`player.gd:87`)과 같은 자리에 얹는다
- 테스트 전략: RED로 "수분 0에서 즉사하지 않음", "포만 0에서 즉사하지 않음", "수분 부족 시 스태미나 회복률 감소", "포만 부족 시 자연 체력 회복 감소", "피로 효과가 기존 계수와 중복 적용돼 폭주하지 않음(합산 상한)", "재접속 스냅샷 복제 유지"를 작성. 기존 `test_survival_stats.gd`의 피로 계약을 깨지 않게 유지.
- 난이도: M
- 비고: 이 태스크가 해체 산출인 날고기에 의미를 준다. 생존 수치 계수(`survival_config.gd:31-52`)는 `.tres`가 override하지 않아 스크립트 기본값이 그대로 쓰인다 — 새 계수도 같은 자리에 두고 `.tres` 분리는 §6 부채로 남긴다.

### W5-T6. 섭취 행동: 날고기 소비와 포만 회복

- 목표: 포만 회복 수단을 만든다. 회복 수단이 없으면 T5는 편도 게이지일 뿐이라 결정이 생기지 않는다.
- 대상 파일: 신규 `scripts/survival/consume_action.gd`, `tests/survival/test_consume.gd`; 수정 `scripts/resources/item_data.gd`(`nutrition`/`hydration` 필드 추가), `data/items/raw_meat.tres`, `scripts/survival/net_survival.gd`(호스트 권위 소비 확정)
- 의존성: W5-T5
- 테스트 전략: RED로 "호스트가 보유 수량을 검증하고 1개만 소비", "포만 회복량이 `ItemData`에서 옴(하드코딩 금지)", "클라이언트가 회복량·수량을 주장해도 거부", "보유하지 않은 아이템 섭취 거부", "포만 상한 초과 없음"을 작성.
- 난이도: S~M
- 비고: 정본 §14.2의 `river_water`/질병 위험은 정식 범위다. 이번엔 날고기 하나로 루프만 닫는다.

### W5-T7. 인벤토리·노트 열람 화면 (Tab)

- 목표: 16칸·무게·관찰문 목록을 읽을 수 있는 전체 화면을 만든다. 해체의 "3~6칸을 쓸 것인가" 결정을 플레이어가 볼 수 있게 한다.
- 대상 파일: 신규 `scenes/ui/inventory/inventory_screen.tscn`, `scenes/ui/inventory/inventory_screen.gd`, `tests/ui/test_inventory_screen.gd`; 수정 `project.godot`(`[input]`에 `toggle_inventory`), `scenes/main.tscn`, `scenes/ui/hud/hud.gd`(슬롯 라벨 격자를 화면으로 이관)
- 의존성: 기존 `Inventory`(16칸·무게), `CraftingKnowledge`(관찰문 32개)
- 테스트 전략: RED로 "Tab 토글로 열고 닫힘", "슬롯·총무게·상한 표시가 `Inventory` 상태와 일치", "관찰문이 목록으로 누적 표시(덮어쓰기 아님)", "열린 동안 게임 입력(이동·해체)이 새지 않음", "싱글에서만 일시정지, 협동에서는 시간이 계속 간다"를 작성. `_press_key` 방식의 실기 InputEvent 주입(`tests/survival/test_interactor_input_route.gd` 패턴)을 재사용한다.
- 난이도: M~L
- 비고: **이 태스크가 Tab/`ui_focus_next` 충돌을 현실화시킨다.** `project.godot:75-82` 주석이 예고한 바로 그 시점이다 — 지금 Tab이 `_unhandled_input`까지 내려오는 건 포커스를 받는 Control이 없기 때문이고, 이 화면이 생기는 순간 Viewport가 Tab을 포커스 이동으로 먹는다. 착수 전 §6의 대응 중 하나를 먼저 고르고 계측으로 확인한다.

### W5-T8. 랩터 무리 조사와 측면 포위

- 목표: 해체 중 노출 20~40초에 실제 판돈을 붙인다. 랩터 2마리가 같은 단서에 서로 다른 접근 각으로 붙고, 고립된 대상을 우선한다.
- 대상 파일: 신규 `scripts/creature/pack_coordinator.gd`, `tests/creature/test_raptor_pack.gd`; 수정 `scripts/creature/raptor.gd`, `scripts/creature/creature_data.gd`, `data/creatures/raptor.tres`, `scenes/main.tscn`(랩터 1→2)
- 의존성: 없음(선행 없이 착수 가능). 단, `sense_loop_harness` 기대값 갱신이 필요할 수 있다
- 테스트 전략: RED로 "같은 단서에 2마리가 서로 다른 접근 각을 배정받음", "동반자와 떨어진 플레이어를 우선 대상으로", "무리 조율이 없어도 1마리는 기존 동작 그대로(회귀)", "조율 상한을 넘으면 개별 행동으로 폴백", "플레이어 실시간 좌표 추적 금지(정본 §15.5)"를 작성. 기존 `test_raptor_states.gd`·`test_raptor_hearing.gd`·`test_raptor_search.gd`를 깨지 않게 유지.
- 난이도: L
- 비고: 판정 문장에 직접 기여하지는 않고 판돈만 올린다. **시간이 부족하면 이 태스크를 가장 먼저 잘라낸다** — 해체 루프의 위험은 랩터 1마리로도 성립한다. `raptor.gd`는 잘 테스트된 파일이라 회귀 위험이 가장 큰 태스크이기도 하다.

### W5-T9. 해체 루프 하네스와 성능 기준선 갱신

- 목표: W5~6 판정을 사람 감상에 두지 않고 고정 시드 10개로 자동 확인한다. 냄새 원천이 늘어난 뒤 성능 회귀를 묶는다.
- 대상 파일: 신규 `scripts/world/butcher_loop_harness.gd`, `tests/world/test_butcher_loop_contract.gd`, `docs/technical/BASELINE_W5_6_BUTCHER.csv`/`.json`; 수정 `tests/perf/*`
- 의존성: W5-T1~W5-T8
- 테스트 전략: GUT와 별도로 headless 하네스 실행. 각 시드에서 "해체 1회 이상 완료", "해체 소음/피 냄새로 랩터 조사 전환 1회", "철수 성공과 실패가 모두 시드 집합 안에서 관측", "냄새 활성 셀이 상한 이하", "해체 구간의 p95가 기준선 대비 악화 시 실패"를 판정한다. `sense_loop_harness`(seed 4001~4010)는 그대로 두고 새 시드 대역을 쓴다.
- 난이도: M
- 비고: W3~4의 `W4-T4`/`W4-T5`와 같은 역할이다. 냄새 원천이 사체 80까지 올라가므로 `W4-T5`의 기준선을 그대로 두면 판정이 흐려진다.

## 5. 권장 순서

| 순위 | 태스크 | 이유 |
|---:|---|---|
| 1 | W5-T4 | 작고 선행이 없다. T2가 지급할 아이템 id가 먼저 존재해야 한다 |
| 2 | W5-T1 | 사체와 홀드가 없으면 이후 전부가 얹힐 자리가 없다 |
| 3 | W5-T2 | 보상 절반. 호스트 권위를 처음부터 넣지 않으면 나중에 못 넣는다 |
| 4 | W5-T3 | 위험 절반. 판정 문장의 "피 냄새와 소음"이 여기서 생긴다 |
| 5 | W5-T5 | 해체 산출인 날고기에 의미를 준다. 선행이 없어 1~4와 병렬 |
| 6 | W5-T6 | 회복 수단이 없으면 T5가 편도 게이지로 끝난다 |
| 7 | W5-T7 | 무게·슬롯 압박과 관찰문을 못 읽으면 결정이 시스템에만 있고 플레이어에게는 없다 |
| 8 | W5-T8 | 판돈 인상. 판정 문장에 간접 기여이고 회귀 위험이 가장 크다. 시간이 부족하면 첫 번째로 잘라낸다 |
| 9 | W5-T9 | 기능이 다 들어온 뒤 판정 증거와 성능 회귀를 묶는다 |

### 5.1 병렬 워커 파일 소유권

같은 워크트리 병렬 작업은 W5에서 태스크별 파일 소유권을 스펙에 명시해 충돌 0건으로 끝냈다(`W5_CRAFTING_MVP_VERIFICATION.md` §5). 같은 방식을 유지한다.

| 레인 | 태스크 | 단독 소유 파일 |
|---|---|---|
| **A — 해체 코어** | T1 → T2 → T3 | `scripts/world/carcass*.gd`, `scripts/world/net_butcher.gd`, `data/creatures/carcass_*.tres`, `data/senses/noise_butcher.tres`, `scripts/net/net_resync.gd`, `scenes/props/survival_demo.tscn`, `tests/world/*`, `tests/senses/test_carcass_senses.gd` |
| **B — 자원과 생존 압박** | T4 → T5 → T6 | `data/items/*`, `data/recipes/*`, `scripts/resources/item_data.gd`, `scripts/survival/survival_stats.gd`, `scripts/survival/survival_config.gd`, `scripts/survival/stamina_component.gd`, `scripts/survival/consume_action.gd`, `scripts/survival/net_survival.gd`, `scripts/player/player.gd`, `tests/survival/*`, `tests/crafting/*` |
| **C — 표면과 위협** | T7 → T8 | `scenes/ui/**`, `project.godot`, `scenes/main.tscn`, `scripts/creature/*`, `data/creatures/raptor.tres`, `tests/ui/*`, `tests/creature/*` |

경계에서 조심할 것:

- `scenes/props/survival_demo.tscn`은 T1(사체 배치)과 T4(손배치 `bone` 축소)가 함께 건드린다. **레인 A가 소유**하고 T4는 필요한 변경을 A에 요청한다.
- `scripts/net/net_resync.gd`는 T2(사체 `yield_mask`)만 수정한다. T5의 생존 수치는 이미 복제되고 있으므로 레인 B는 이 파일을 열 필요가 없다.
- `scenes/main.tscn`은 T7(인벤토리 화면)과 T8(랩터 1→2)이 함께 건드린다. 둘 다 **레인 C** 안이라 순차 처리하면 된다.
- `data/creatures/`는 A(`carcass_*.tres`)와 C(`raptor.tres`)가 나눠 쓴다. 파일이 달라 충돌하지 않는다.
- 병렬 작업 중 전체 GUT는 타 워커의 중간 상태에 오염될 수 있다(W5에서 `game_data.gd` 파스 에러 사례). 워커는 범위 축소 실행만 하고 **전체 회귀는 코디네이터가 통합 시점에** 돌린다.

## 6. 잠재 장애 요소와 기술 부채

### Tab과 `ui_focus_next` 충돌 — T7의 선행 결정

`project.godot:75-82`의 주석이 예고한 상황이 T7에서 현실이 된다. 지금 Tab이 게임 입력까지 내려오는 이유는 포커스를 받는 Control이 하나도 없어서다(계측으로 확인된 사실이다). 인벤토리 화면이 생기면 `Viewport`가 Tab을 포커스 이동으로 소비하기 시작한다. 대응은 셋 중 하나이고, **착수 전에 고르고 계측으로 확인한다.**

1. `InputMap`에서 `ui_focus_next`/`ui_focus_prev`의 Tab 바인딩을 제거하고 화면 내 포커스 이동은 방향키/명시 바인딩으로 처리한다. 게임 전체가 마우스+키 조작이라 Tab 포커스 순회에 의존하는 화면이 없으므로 실효 손실이 가장 작다.
2. 인벤토리 토글만 `_input` 단계에서 처리해 GUI보다 먼저 가로챈다. 다만 다른 UI가 늘어날 때마다 같은 판단을 반복해야 한다.
3. 토글을 Tab이 아닌 키로 옮긴다. HUD 목업(`docs/design/07-16`)이 Tab을 인벤토리로 예약해 뒀으므로 설계 변경이 필요하다.

W5의 교훈대로 **추측 수정 금지**다. `cycle_target` 버그는 GUT가 함수를 직접 호출해 통과하는 바람에 실기에서만 드러났다. T7의 테스트는 반드시 리터럴 키를 `push_input`으로 주입하는 방식이어야 한다.

### 네트워크 동기화

- 해체 산출·소음·냄새는 전부 호스트 권위여야 한다. 클라이언트가 "조용히 해체했다", "이 bit는 아직 안 받았다", "산출은 뼈 3개였다"를 확정하면 W2에서 막은 변조 경로가 다시 열린다.
- `yield_mask`는 재접속 스냅샷 대상이다. 현재 `NetResync`는 플레이어 중심(인벤토리·체력·출혈·부위·생존수치·위치·지식)이고 월드 오브젝트 상태를 담지 않는다. 사체가 첫 사례이므로 "플레이어 스냅샷"과 "월드 스냅샷"의 경계를 여기서 처음 긋게 된다 — 구조를 크게 만들지 말고 사체 배열 하나만 추가한다.
- 동시 해체가 실제 동시성 버그의 진입점이다. 두 플레이어가 같은 사체에 붙는 상황을 테스트로 먼저 만든다.
- 인벤토리 만석에서 산출 지급이 실패할 때 bit를 소모하면 자원이 조용히 증발한다. 지급 성공과 bit 확정을 한 트랜잭션으로 묶는다. `Crafting.craft()`가 이미 "재료 제거 후의 무게·슬롯 여유를 먼저 시뮬레이션하고 실패 시 인벤토리를 바꾸지 않는" 패턴을 갖고 있으므로 그걸 따른다.

### 성능 예산

- 냄새 원천 강도가 사체 80까지 올라간다(현재 최댓값은 출혈·`bait` 55). 활성 셀 수가 늘어나므로 `W4-T5`의 기준선(`BASELINE_W3_4_SENSE_LOOP.*`)을 그대로 두면 판정이 흐려진다. T9에서 새 기준선을 뜬다.
- 랩터를 2마리로 올려도 정본 §15.3의 상한(완전 AI 24, 추격 12, 프레임당 새 경로 요청 4)에는 한참 못 미친다. **공간 해시 전환은 아직 필요 없다.** 다만 `pack_coordinator`가 매 틱 그룹을 재조회하면 그 자체가 W3~4에서 막은 패턴이므로, 조율은 랩터의 기존 `ai_tick_interval`(0.2초) 안에서만 돈다.
- 해체는 홀드 중 `_process`가 도는 구간이다. `Interactor`가 이미 "홀드 중에만 `_process`를 켜는" 패턴을 쓰므로 사체도 같은 규칙을 따른다. 사체가 배회 중에도 매 프레임 무언가를 하면 안 된다.
- 인벤토리 화면은 열려 있는 동안에만 갱신하고, `Inventory.changed` 신호로만 다시 그린다. 매 프레임 폴링은 HUD에서 이미 금지한 패턴이다(성능문서 6.2).

### 설계 부채

- **세션 길이가 두 곳에 중복.** `session_clock.gd:15-19`의 스크립트 기본값과 `scenes/main.tscn:91-94`의 씬 override가 같은 값을 각각 갖는다. `total_days`는 `@export`라 코드 수정 없이 바꿀 수는 있지만 진실의 원천이 둘이라 drift 위험이 있다. 7일 확장을 실제로 할 때 `SessionConfig` 리소스로 합치는 게 맞고, 지금 하면 이번 판정에 기여하지 않는 리팩터링이다.
- **`SurvivalConfig` 비대화.** W3~4에서 이미 지적했고 T5가 수분·포만 계수를 더 얹는다. 현재 `data/survival/survival_config.tres`는 생존 수치 그룹을 override조차 하지 않아 스크립트 기본값이 사실상 정본이다. 분리는 계수 튜닝이 실제로 시작될 때 한다.
- **`craft_bone_scraper` 재료가 정본과 불일치.** T4가 해소한다. 힘줄이 없어서 생긴 임시 조합이었고, 해체가 힘줄을 공급하면 정본으로 돌아간다.
- **랩터에 체력·사망이 없다.** 이건 부채가 아니라 의도다 — §7 참조.
- **`bone`의 유일한 출처가 데모 씬 손배치.** T1/T4가 해소한다. 정본 §14.5의 `SpawnTable`·시드 자원 군집은 W7~8의 청크 작업과 함께이므로, 이번엔 데모 씬에 사체를 시드 배치하는 수준까지만 간다.

### 가짜 완료 방지

- 완료 판정은 주석·TODO 제거·디버그 표시가 아니라 실제 상태 변화와 하네스 로그다.
- 각 비자명 태스크는 RED→GREEN 증거를 남긴다. 최소 단위는 GUT 실패 테스트 1개와 성공 로그다.
- `rg 'TODO|FIXME|HACK|pass$|assert_true(true)|assert_false(false)|# func test_|skip|pending' scripts tests`를 태스크 종료마다 실행한다.
- **각 태스크는 GUT 통과만으로 완료가 아니다.** 통합 시점에 실기 플레이로 해체 1회를 눈으로 확인한다. W5에서 자동 테스트를 전부 통과하고도 실기에서 깨진 사례가 2건이었다.

### 운영 메모 (W5 오케스트레이션에서 이월)

- codex 계열 워커는 `-c sandbox_workspace_write.network_access=true` 없이는 Orca RPC와 ENet 테스트가 모두 막힌다. claude 워커는 제약 없음.
- 워커 샌드박스에서 Godot이 `user://` 접근 실패로 크래시할 수 있다. `HOME=/tmp/pn-godot-home` 우회를 쓰거나 전체 GUT는 코디네이터가 대행한다.
- `.godot/` 임포트 캐시가 없는 환경에서는 첫 실행이 클래스 해석 실패로 통째로 깨진다. `godot --headless --path . --import`를 먼저 한 번 돌린다.

## 7. 이번 범위에서 하지 않을 것

- **랩터 사망·전투·시체화.** 사체는 정본 §14.5·§22.2에서 **시드 배치 월드 오브젝트**(`carcass_small/medium/large` SpawnTable, §10.3 시드 고정 수량과 `yield_mask`)이지 개체를 죽여서 만드는 산물이 아니다. 현재 랩터에는 체력 컴포넌트조차 없고, 이건 부채가 아니라 "죽이는 재미가 아니라 피하는 재미" 원칙의 결과다. 해체 루프에 전투는 필요 없다.
- **두 번째 공룡(청소형 D03/D04).** 사체와 가장 잘 어울리는 종이라 유혹이 크지만, 해체 루프의 위험은 기존 랩터로 이미 성립한다. 청소형은 해체가 검증된 **뒤에** 그 위에 얹는 게 순서다. 정본 §22.1의 MVP AI 3유형 상한 안에 여유가 있으므로 다음 마일스톤 후보로 남긴다.
- **7일 세션 확장 — 3일을 유지한다.** `total_days = 7`은 한 줄이지만 그게 요점이 아니다. 정본 §18.1은 4~7일 구간을 대이동→화산재→분화와 부품 B/C로 정의하고, 그 콘텐츠(5 Zone·대표 공간·부품 루프)는 W7~8 이후 관문이다. 지금 7일로 늘리면 같은 30분 루프를 70분 동안 두 번 더 반복시키는 것이고, 판정이 좋아지기는커녕 흐려진다. 부수 효과로 실기 플레이 1회가 70분이 되어 반복 검증 속도도 절반 이하로 떨어진다. **7일 확장은 Zone·공간·부품 콘텐츠가 들어오는 마일스톤과 같은 판에서 한다.**
- **가죽(`dinosaur_hide`)과 건조대.** 해체 산출은 날고기·뼈·힘줄 3종으로 간다. 가죽의 유일한 소비처가 가죽 망토이고 그건 건조대(나무 3+섬유 2, 1일)를 함께 만들어야 성립한다. 설비 1종 + 아이템 2종 + 건조 시간 규칙을 이번 판정 문장에 기여하지 않는 채로 얹게 된다. 3종만으로도 "무엇을 몇 칸까지 가져갈 것인가"라는 정본 §14.4의 선택은 이미 성립한다. 가죽·건조대·말린고기는 설비 마일스톤에서 묶어서 한다.
- **활·특수 화살 6종, 수지 화염 분사 장비.** 정본 §14.3이 명시적으로 정식 확장 후보로 두고 "MVP에는 넣지 않는다"고 못박은 항목이다.
- **청크 스트리밍·타일 수직 조각·`SpawnTable` 시드 생성.** 정본 §23의 W7~8이다. 이번 사체는 데모 씬 시드 배치까지만 간다.
- **디스크 저장·마이그레이션.** 정본 §22.4 기준 W14 관문이다. `yield_mask`는 세션 내 메모리 권위와 재접속 스냅샷까지만 다룬다.
- **음식 부패, 질병, 부위 부상 확장.** 각각 정본 §13에서 정식 버전 또는 "가능하면 포함"이다. 날고기 신선/상함 2단계와 오염 물 질병은 건조대·정수와 한 묶음이라 위 항목과 함께 미룬다.
- **완성 에셋.** 에셋 정책에 따라 회색 상자 실루엣과 단계 색, 최소 HUD만 사용한다.

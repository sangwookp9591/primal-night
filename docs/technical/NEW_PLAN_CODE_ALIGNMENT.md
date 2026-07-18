# 새 정본-현행 코드 정렬표

기준 문서: `/Users/psw/Downloads/primitive_survival_game_plan_vs_project_zomboid.md`.
현행 근거: `docs/HANDOFF_NEXT_SESSION.md` §1, `docs/technical/DESIGN_DOC_CODE_ALIGNMENT.md`, 현재 코드베이스.

주의: 이 문서는 제품 결정을 내리지 않는다. 새 정본과 현행 코드가 충돌하는 곳은 "사용자 결정 필요"로만 분리한다.

## 정렬표

| 새 정본 | 분류 | 현행 코드 근거 | 차이 / 메모 |
|---|---|---|---|
| §5 핵심 재미 기둥: 생활 중심, 자기 목표, 죽음 기록 | 부분 구현 | 생존 수치는 체온/수분/포만/피로 중심이고 즉사보다 행동 효율에 연결된다 (`scripts/survival/survival_stats.gd:4`, `scripts/survival/survival_stats.gd:10`, `scripts/survival/survival_stats.gd:98`). 사망 원인 문장과 회고는 있다 (`scripts/session/loop_objective.gd:179`, `scripts/session/character_chronicle.gd:149`, `scripts/ui/pause_menu.gd:53`). | 전투보다 생활이라는 방향은 맞지만, 현재 세션 목표는 추출 지점/4결과 판정에 묶여 있다. 사망 시 이동 거리, 발견 지역, 대표 장비, 마지막 24시간 타임라인, 지도 계승은 아직 없다. |
| §6 핵심 게임 루프: 관찰-탐색-위험-귀환-제작/치료-확장 | 부분 구현 | 이동/은신/소음, 채집, 해체, 모닥불, 치료, 귀환 거점 프롭이 연결돼 있다 (`scripts/player/player.gd:98`, `scripts/world/harvestable_node.gd:98`, `scripts/world/carcass.gd:118`, `scripts/props/net_campfire.gd:211`, `scripts/survival/heal_target.gd:21`, `scenes/main.tscn:51`). | 루프의 작은 절편은 작동한다. 장기 루프의 계절 대비, 희귀 자원, 이동 수단, 복수 거점 확장은 미구현이다. |
| §7 플레이어 캐릭터: 이전 직업/취미/성격/현대 지식/약점/시작 복장 | 부분 구현 | 시작 의상/장비 슬롯은 `outfit/back/main_hand`로 있다 (`scripts/equipment/equipment_component.gd:6`, `data/items/white_underwear.tres`). 제작 지식 관찰 로그는 있다 (`scripts/crafting/crafting_knowledge.gd:46`). | 직업, 취미, 성격, 약점 선택 UI/데이터는 없다. "현대 지식"은 제작 힌트/발견 기록 수준이다. |
| §8 능력 성장: 숙련/이해/적응 | 부분 구현 | `CraftingKnowledge`가 발견한 recipe와 관찰문을 저장한다 (`scripts/crafting/crafting_knowledge.gd:30`, `scripts/crafting/crafting_knowledge.gd:100`). `CharacterChronicle`은 발견 원리 수와 해결 방식 카운트를 저장한다 (`scripts/session/character_chronicle.gd:16`, `scripts/session/character_chronicle.gd:117`). | 숙련 수치, 결과 품질 변화, 환경 적응 시스템은 없다. 현재는 "이해"의 기록 뼈대만 있다. |
| §9 생존 수치: 배고픔/갈증/체온/피로/통증/출혈/감염/정신/체력/젖음/냄새 | 부분 구현 | 체온/수분/포만/피로/젖음/식중독/독성은 `SurvivalStats`에 있다 (`scripts/survival/survival_stats.gd:21`, `scripts/survival/survival_stats.gd:46`, `scripts/survival/survival_stats.gd:179`). 체력/출혈/피 냄새는 `HealthComponent`가 처리한다 (`scripts/survival/health_component.gd:14`, `scripts/survival/health_component.gd:38`, `scripts/survival/health_component.gd:46`). | 통증, 감염, 정신 안정은 별도 시스템이 없다. 표시도 단계형은 있으나 캐릭터 행동/화면 변화까지는 제한적이다. |
| §10 생태계 시스템 | 부분 구현 | 랩터는 시야/소리/냄새/불에 따라 배회-조사-추격-도주한다 (`scripts/creature/raptor.gd:4`, `scripts/creature/raptor.gd:275`, `scripts/creature/raptor.gd:329`). 청소동물은 사체/냄새 먹이를 먹고 플레이어에게서 도망간다 (`scripts/creature/scavenger.gd:4`, `scripts/creature/scavenger.gd:64`, `scripts/creature/scavenger.gd:124`). | 먹이사슬은 랩터+청소동물+사체 소비 수준이다. 초식동물, 조류/어류, 개체군 변화, 영역 확장, 생태 변화는 없다. |
| §10.3 흔적 시스템 | 부분 구현 | 냄새 격자와 바람 이류가 있다 (`scripts/senses/smell_grid.gd:4`, `scripts/senses/smell_grid.gd:19`, `scripts/senses/smell_grid.gd:135`). 출혈 이동은 피 웅덩이와 냄새를 남긴다 (`scripts/survival/blood_trail.gd:4`, `scripts/survival/blood_trail.gd:97`). 소음은 플레이어 자세와 원격 아바타 이동에서 난다 (`scripts/player/player.gd:149`, `scripts/senses/smell_grid.gd:254`). | 냄새, 피, 소리는 구현. 발자국, 배설물, 털, 둥지, 새들의 비행, 진흙 자국은 없다. `ValleyMap`의 `footprints`는 절편 데이터 ref일 뿐 독립 흔적 엔티티가 아니다 (`scripts/world/valley_map.gd:116`). |
| §11 전투 설계 | 부분 구현 | 근접전은 무기 길이/전방 호/쿨다운/스태미나를 호스트가 판정한다 (`scripts/net/net_combat.gd:17`, `scripts/net/net_combat.gd:21`, `scripts/net/net_combat.gd:267`). 활 조준/화살/투사체와 소음도 있다 (`scripts/net/net_combat.gd:219`, `scripts/net/net_combat.gd:280`, `scripts/net/net_combat.gd:296`). 불은 랩터를 물러나게 한다 (`scripts/creature/raptor.gd:281`, `scripts/creature/raptor.gd:303`). | 방향/거리/무기 길이는 있다. 지형, 공포, 자세 전투, 부위별 다중 부상, 덫 전투, 먹이 버리고 탈출은 제한적 또는 없음. |
| §11.3 부위별 부상 | 부분 구현 | `InjuryComponent`는 `head/torso/arm/leg` enum을 갖지만 현재 유효 상태는 다리 열상뿐이다 (`scripts/survival/injury_component.gd:4`, `scripts/survival/injury_component.gd:55`). 다리 열상은 이동 배율을 낮춘다 (`scripts/survival/injury_component.gd:63`). | 손/팔/발/갈비뼈/머리 효과와 부목은 없다. |
| §12 도구와 제작 시스템 | 부분 구현 | 빠른 제작 목록과 레시피 기반 제작이 있다 (`scripts/player/player.gd:7`, `scripts/crafting/crafting.gd:9`). 재료 소모, 결과 수용 가능성, 제작 소음이 처리된다 (`scripts/crafting/crafting.gd:13`, `scripts/crafting/crafting.gd:26`, `scripts/crafting/crafting.gd:36`). | 이름 기반 레시피 중심이다. 단단함/탄성/섬유질 같은 재료 속성 기반 제작, 제작 실패 품질/부산물은 없다. |
| §13 현대 지식 기반 특수 제작 | 부분 구현 | 스마트폰 아이템과 현대 지식 관찰/제작 힌트 저장 구조는 있다 (`data/items/smartphone.tres`, `scripts/crafting/crafting_knowledge.gd:46`). 현재 빠른 제작에는 유인 도구, 뼈 피리, 미끼 주머니가 들어간다 (`scripts/player/player.gd:11`, `scripts/player/player.gd:12`, `scripts/player/player.gd:13`). | 정수 장치, 숯 필터, 도르래, 펌프, 비누, 접착제, 나침반, 렌즈 점화, 원시 화염분사 장치는 없다. |
| §14 불 시스템 | 부분 구현 | 모닥불은 연료 타이머, 점화/소등, 랩터 회피 반경을 가진다 (`scripts/props/campfire.gd:4`, `scripts/props/campfire.gd:59`, `scripts/props/campfire.gd:78`). 모닥불 설치와 고기 굽기는 호스트 권위로 검증된다 (`scripts/props/net_campfire.gd:183`, `scripts/props/net_campfire.gd:211`). | 요리/체온/동물 위협/조명은 일부 구현. 물 정화, 연기 신호, 벌레 방지, 숯/접착제, 산불/연기 중독/옷 착화는 없다. |
| §15 거점 건설 | 부분 구현 | 현재 거점은 고정 위치 프롭 3개: 보관함, 건조대, 잠자리 (`scenes/main.tscn:51`, `scenes/main.tscn:52`, `scenes/main.tscn:55`, `scenes/main.tscn:58`). 보관/건조/휴식 상호작용은 구현되어 있다 (`scripts/props/net_base_camp.gd:24`, `scripts/props/net_base_camp.gd:72`, `scripts/props/net_base_camp.gd:113`). | 자유 건축, 위치별 장단점, 빗물 수집, 방어 구조, 기록 보관, 꾸미기/기념품은 없다. |
| §16 의복과 장비 시각화 | 이미 구현됨 | 장비 슬롯은 `outfit/back/main_hand`이고 장비 변경은 VisualRig 레이어로 반영된다 (`scripts/equipment/equipment_component.gd:6`, `scripts/player/player_visual_rig.gd:4`, `scripts/player/player_visual_rig.gd:88`). 모피 망토/갈대 우비/뼈 갑옷은 외형 ID와 modifier를 가진다 (`data/items/fur_cloak.tres:10`, `data/items/reed_raincoat.tres:10`, `data/items/bone_armor.tres:10`). | 새 정본의 모든 세부 슬롯(신발/장갑/머리/장신구/붕대/부목)은 없다. 그러나 현행 완성 축 기준으로 캐릭터 외형 반영은 가장 앞선 영역이다. |
| §17 탐험과 월드 설계 | 부분 구현 | 40청크 문서 골격과 랜드마크 ID가 있고, 현재 플레이는 Z01-Z03 절편으로 제한된다 (`scripts/world/valley_map.gd:43`, `scripts/world/valley_map.gd:55`, `scripts/world/valley_map.gd:78`). 자원/위험/랜드마크 밀도 규칙도 있다 (`scripts/world/valley_map.gd:91`, `scripts/world/valley_map.gd:104`). | 수작업+시드 변형 골격은 있다. 최소 4개 바이옴, 절차 동굴/폐허, 여러 시작 위치, 동물 이동 시뮬레이션은 없다. |
| §18 지도 시스템 | 미구현 | 저장 스냅샷에는 난이도/플레이어/시계/날씨/목표/기록/월드 아이템/거점/사체/개체 상태가 있으나 지도 상태는 없다 (`scripts/save/save_service.gd:96`, `scripts/save/save_service.gd:114`, `scripts/save/save_service.gd:123`). 파일 검색상 지도 전용 구현은 `ValleyMap` 월드 타일맵뿐이다 (`scripts/world/valley_map.gd:1`). | 플레이어가 직접 기록하는 지도, 지도 소지품, 지도 손실/회수 모드 모두 없음. |
| §19 사건 시스템 | 미구현 | 전역 이벤트 버스는 소리/냄새/피해/출혈/아이템/모닥불 신호만 가진다 (`scripts/core/event_bus.gd:3`). `main.tscn`에도 EventDirector 계열 노드는 없다 (`scenes/main.tscn:39`, `scenes/main.tscn:180`). | 조건 기반 사건, 장기 결과 유지, 오염/홍수/산불/무리 이동/가뭄/현대 물품 표류는 없다. 단, 날씨/비는 사건 후보 자산이다. |
| §20 귀환과 미스터리 | 부분 구현 | `LoopObjective`에는 균열/탈출/남음 4결과와 환경 문장이 있다 (`scripts/session/loop_objective.gd:13`, `scripts/session/loop_objective.gd:33`, `scripts/session/loop_objective.gd:34`). `ValleyMap` 랜드마크에는 추락흔, 침수 관측소, 신호대 같은 단서명이 있다 (`scripts/world/valley_map.gd:65`). | 메인 퀘스트 마커 없는 단서 탐사는 아직 표현 수준. 유물/벽화/비정상 동물/다른 생존자 흔적/귀환 포기 선택의 장기 구조는 없다. |
| §21 솔로 플레이 완결 범위 | 현행과 충돌 | 새 정본은 첫 출시 멀티 제외를 명시하지만, 현행 코드는 host+3 수용이다 (`scripts/net/net_config.gd:10`). 타이틀도 싱글/호스트/참가를 제공한다 (`scenes/ui/title/title_screen.gd:36`, `scenes/ui/title/title_screen.gd:38`, `scenes/ui/title/title_screen.gd:39`). host+3 soak 하네스도 있다 (`scripts/net/four_player_soak_harness.gd:3`, `scripts/net/four_player_soak_harness.gd:15`). | 사용자 결정 필요. 아래 충돌 목록 1 참조. |
| §22 MVP 범위 | 부분 구현 | MVP 월드 후보 중 숲/강/동굴/절벽/작은 습지는 `ValleyMap` 랜드마크/존에 일부 있다 (`scripts/world/valley_map.gd:65`, `scripts/world/valley_map.gd:78`). 제작물 일부(창/활/화살/횃불/가방/건조대)는 데이터/레시피가 있다 (`data/recipes/craft_stone_spear.tres`, `data/recipes/craft_bow.tres`, `data/recipes/craft_torch.tres`, `data/recipes/craft_small_pack.tres`, `data/recipes/craft_drying_rack.tres`). | 동물 6종, 물통/덫/화덕/간단한 구조물, 갈증을 회복할 물원, 감염, 동물 이동/식량 부패/산불 사건은 미구현 또는 제한적. |
| §23 Project Zomboid에서 배울 점/개선점 | 부분 구현 | 죽음 원인 명확화, 플레이 기록, 샌드박스 난이도 축, 장비/상태 상호작용 일부가 있다 (`scripts/session/loop_objective.gd:179`, `scripts/session/character_chronicle.gd:149`, `scripts/difficulty/difficulty_config.gd:8`, `scripts/resources/item_data.gd:20`). | 후반 목표, 자연스러운 튜토리얼, 숙련 자동화, 루팅 반복 대체 생태 탐색은 아직 설계/로드맵 영역이다. |
| §24 난이도와 샌드박스 설정 | 부분 구현 / 현행과 충돌 | 현행 프리셋 ID는 `gentle/standard/harsh`이고 표시명은 온화/표준/가혹이다 (`scripts/difficulty/difficulty_runtime.gd:4`, `resources/difficulty/gentle.tres:7`, `resources/difficulty/standard.tres:7`, `resources/difficulty/harsh.tres:7`). 축은 자원, 흔적 가독성, 사망 복구, 포식자 관용도다 (`scripts/difficulty/difficulty_config.gd:8`, `scripts/difficulty/difficulty_config.gd:12`, `scripts/difficulty/difficulty_config.gd:16`, `scripts/difficulty/difficulty_config.gd:19`). | 새 정본 명칭은 탐험가/생존자/표류자. 세부 설정 중 동물 수, 질병, 식량 부패, 계절, 화재 확산, 귀환 단서 빈도는 없다. |
| §25 스트리머/시청자 재미 | 부분 구현 | 캐릭터 외형 변화와 상태 오버레이, 랩터 감지 텔레그래프, 사망 원인 문구가 있다 (`scripts/player/player_visual_rig.gd:16`, `scripts/creature/raptor.gd:23`, `scripts/session/loop_objective.gd:179`). | 거점 화재, 절벽 추락, 구조 붕괴, 대형 동물 사냥, 장비 손상 시각화 대부분은 없다. |
| §26 플레이 예시 | 부분 구현 / 현행과 충돌 | 첫날 강가/절벽/동굴 주변 탐색, 돌/나무/섬유/열매/흔적/랩터 위험의 절편은 있다 (`scripts/world/valley_map.gd:104`, `scripts/world/harvestable_node.gd:10`, `scripts/items/world_item.gd:10`). 현행 세션은 3일 압축이다 (`scripts/session/session_clock.gd:4`, `scenes/main.tscn:161`). | 7일째/30일째 장기 생존 예시는 현행 3일 압축 구조와 충돌한다. 사용자 결정 필요. |
| §27 최종 게임 정체성 | 부분 구현 | "내 흔적 때문에 사냥당한다"는 현행 축은 냄새/피/소리/랩터 조사에 강하게 구현되어 있다 (`scripts/senses/smell_grid.gd:4`, `scripts/survival/blood_trail.gd:4`, `scripts/creature/raptor.gd:275`). | 새 정본은 공룡 자체보다 자연 이해와 생활 반경을 강조한다. 현행 랩터 중심 위협을 어떻게 낮추거나 생태계로 확장할지 결정이 필요하다. |
| §28 핵심 개발 우선순위 | 부분 구현 | 이동/상호작용, 탐색/채집/운반, 불/체온/수면, 도구 제작, 거점, 동물 행동/흔적, 부상/치료, 날씨, 장비 외형, 기록은 모두 최소 절편이 있다 (`scripts/player/player.gd:98`, `scripts/world/harvestable_node.gd:98`, `scripts/props/campfire.gd:59`, `scripts/props/net_base_camp.gd:113`, `scripts/weather/net_weather.gd:1`, `scripts/session/character_chronicle.gd:1`). | 우선순위 9 탐험 보상, 11 사건, 12 장기 미스터리는 약하다. 로드맵은 이 순서를 유지하되 새 아이템 폭증 없이 기존 자산 재조합을 우선한다. |

## 충돌 목록: 사용자 결정 필요

### 1. 멀티플레이: host+3 구축 vs 첫 출시 솔로 전용

- 현행 유지: 이미 `max_clients = 3`이고 타이틀은 싱글/호스트/참가를 제공한다 (`scripts/net/net_config.gd:10`, `scenes/ui/title/title_screen.gd:36`). host+3 soak는 네 개 `main.tscn` 브랜치의 이동/인벤토리/장비/세션 결과/재접속을 검증한다 (`scripts/net/four_player_soak_harness.gd:3`, `scripts/net/four_player_soak_harness.gd:174`).
- 유지 비용/리스크: 모든 신규 생태/사건/지도/저장 시스템에 호스트 권위와 복제/재접속 테스트가 붙는다. 솔로 감정에 맞춘 UX보다 동기화 안전성이 계속 우선순위를 먹는다. 새 정본 §21.2와 마케팅 메시지가 충돌한다.
- 전환 비용/리스크: 호스트/참가 UI를 숨기거나 비출시 플래그로 묶고, 멀티 하네스를 내부 회귀로만 유지해야 한다. 이미 통과한 host+3 자산을 버리지는 않지만 출시 QA 범위와 문서가 바뀐다. 멀티 기반으로 설계된 코드 경계가 많아 제거보다 비노출이 안전하다.

### 2. 공룡/랩터 정체성: 현행 중심 위협 vs "좀비->공룡 스킨 교체" 회피

- 현행 유지: `Raptor`는 단순 적이 아니라 소리/냄새/시야/불을 읽는 위협이며, 감지 루프의 핵심이다 (`scripts/creature/raptor.gd:4`, `scripts/creature/raptor.gd:275`). 사망 원인도 피 냄새/소음/유인 냄새 중심으로 설명된다 (`scripts/session/loop_objective.gd:191`, `scripts/session/loop_objective.gd:195`, `scripts/session/loop_objective.gd:199`).
- 유지 비용/리스크: 랩터가 계속 제품의 첫 인상이 되면 새 정본 §4.1이 경고한 "좀보이드 원시시대 모드" 오해가 남는다. 초식동물/작은 생태/환경 재난보다 포식자 전투/회피가 커질 위험이 있다.
- 전환 비용/리스크: 랩터를 삭제하지 않고 "중형 포식자 중 하나"로 격하하려면 초식동물, 물가 흔적, 둥지, 사체 경쟁, 계절 이동 등 주변 생태 시스템이 먼저 필요하다. 단기적으로는 현행 재미 축이 희석되고 플레이테스트 비교가 어려워진다.

### 3. 세션 구조: 3일 압축·4결과 vs 자유 생존

- 현행 유지: 세션은 낮 7분+황혼 1분+밤 2분의 3일 구조이고, 결과는 `STABLE_ESCAPE/FORCED_ESCAPE/REMAIN/FAILED` 네 가지다 (`scripts/session/session_clock.gd:4`, `scripts/session/session_clock.gd:15`, `scripts/session/loop_objective.gd:13`). 만료 시 생존 여부로 `REMAIN/FAILED`를 확정한다 (`scripts/session/loop_objective.gd:236`).
- 유지 비용/리스크: 20-30분 검증 절편은 선명하지만, 새 정본 §5.2/§20.2의 자율 목표·귀환 선택·자유 생존과 충돌한다. 7일/30일 플레이 예시를 그대로 지원하지 못한다.
- 전환 비용/리스크: 자유 생존으로 바꾸면 저장, 사건 지속, 지도, 장기 동기, 사망 기록이 먼저 필요하다. 기존 하네스와 세션 판정 테스트를 "튜토리얼/챌린지 모드"로 낮출지 폐기할지 결정해야 한다.

### 4. 난이도 명칭: 온화/표준/가혹 vs 탐험가/생존자/표류자

- 현행 유지: 코드 ID는 `gentle/standard/harsh`, 표시명은 온화/표준/가혹이다 (`scripts/difficulty/difficulty_runtime.gd:4`, `resources/difficulty/gentle.tres:8`, `resources/difficulty/standard.tres:8`, `resources/difficulty/harsh.tres:8`). 난이도는 자원/흔적/사망 복구/포식자 축에 실제 연결된다 (`scripts/difficulty/difficulty_config.gd:8`).
- 유지 비용/리스크: 기능명은 명확하지만 새 정본의 생존 판타지 어휘와 덜 맞는다. "가혹"은 플레이어 정체성보다 벌칙 느낌이 강하다.
- 전환 비용/리스크: 표시명만 바꾸면 비용은 작다. ID까지 바꾸면 저장 파일의 `difficulty` 값, 테스트, 리소스 경로, 문서가 흔들린다 (`scripts/save/save_service.gd:96`, `scripts/save/save_service.gd:130`). 권장 전환 단위는 ID 유지 + display_name/문구 변경이다.

## 3단계 로드맵 초안

원칙: 새 정본 §28의 순서를 따르되, 충돌 결정 전에도 안전한 작업만 고른다. 새 아이템 수를 늘리기보다 기존 냄새/소리/피/날씨/거점/기록 자산을 재조합한다.

### 1단계: 30분 생활 루프 밀도 보강

목표: §28.1-§28.4, §28.6-§28.7을 강화한다.

- 채집/운반/귀환: 기존 `HarvestableNode`, `WorldItem`, 인벤토리 무게/슬롯을 활용해 "나가서 얻고, 냄새/소리 위험을 안고, 거점으로 돌아오는" 이유를 늘린다.
- 흔적 가독성: 새 동물보다 먼저 발자국/배설물 전체 구현 대신, 현행 `ValleyMap.SLICE_ENCOUNTERS`의 `trace` ref를 실제 상호작용 가능한 짧은 흔적 프롭으로 승격한다. 첫 대상은 발자국/꺾인 가지/먹다 남은 사체 중 1-2개로 제한한다.
- 부상/치료: 기존 다리 열상/붕대/피 흔적을 더 명확히 보여 주고, 부목 같은 새 시스템은 보류한다.
- §4 판정: "공룡 스킨 교체"가 아니라 흔적 판단이 재미를 만들었는지 확인한다. 반복 클릭을 늘리지 않고 기존 홀드/상호작용 틀 안에서 해결한다.
- §22.1 판정: 30분 생존이 재미있는가, 탐험 후 거점 귀환이 기대되는가, 같은 상황에 여러 해결법이 있는가를 우선 측정한다.

### 2단계: 거점-날씨-탐험 보상 연결

목표: §28.3, §28.5, §28.8-§28.10을 강화한다.

- 거점 기능: 보관함/건조대/잠자리를 유지하면서, 비 예고와 젖음/체온/의복 modifier가 거점 귀환 판단에 더 크게 작동하게 한다.
- 탐험 보상: 새 희귀 아이템보다 안전한 이동로, 자연 바람막이, 수원 후보, 위험 구역 메모 같은 보상을 먼저 추가한다. 지도 시스템 결정 전에는 `CharacterChronicle` 또는 HUD 임시 기록으로 제한한다.
- 장비 외형: 이미 강한 축이므로 새 슬롯보다 기존 의복 상태(젖음/손상/수선 흔적)를 더 읽히게 만든다.
- §4 판정: 불편한 세부 조작이 아니라 결과의 설득력으로 현실성을 보여 주는지 확인한다.
- §22.1 판정: 플레이어가 스스로 다음 목표를 정하는가, 죽었을 때 다시 시작하고 싶은가를 본다.

### 3단계: 사건/기록/미스터리의 최소 영속 구조

목표: §28.9, §28.11-§28.12를 시작한다.

- 사건 시스템: 완전한 EventDirector보다 기존 `EventBus`, `NetWeather`, `SaveService`에 얹을 수 있는 2-3개 조건 사건부터 만든다. 예: 폭우로 여울 위험 증가, 바닥 고기 방치 시 청소동물 접근, 멀리 보이는 연기 힌트.
- 기록 확장: `CharacterChronicle`에 이동 거리, 발견 랜드마크, 마지막 주요 사건을 추가해 사망 화면과 이어하기 요약을 강화한다.
- 장기 미스터리: 새 퀘스트 마커 없이 `ValleyMap.LANDMARK_LABELS`의 추락흔/침수 관측소/검은 능선 신호대를 조사 기록으로 연결한다.
- §4 판정: 퀘스트 목록을 복제하지 않고 환경 단서와 플레이어 기록으로 동기를 만드는지 확인한다.
- §22.1 판정: 플레이 과정에서 이야기할 만한 사건이 발생하는가를 주요 관문으로 둔다.

## 결정 전 진행 가능한 다음 작업 후보

1. `trace` 프롭 1차: 발자국/꺾인 가지/먹다 남은 사체 중 2개만, 기존 `ValleyMap.SLICE_ENCOUNTERS` 위치와 `SenseIndicator` 피드백 재사용.
2. 사망/회고 강화: `CharacterChronicle`에 이동 거리와 발견 랜드마크 카운트 추가. 지도 시스템 결정보다 작고, §5.3/§22.1에 바로 기여한다.
3. 비-거점 연결: `NetWeather` 경고, 젖음, 의복 modifier, 잠자리 휴식의 체감 연결을 테스트로 고정.
4. 난이도 표시명 결정 대기: ID 변경 없이 display_name만 바꾸는 경로를 준비하면 저장 호환 리스크가 작다.

## 검증 메모

- 이 문서는 코드 변경 없이 작성했다.
- 현행 작업 트리는 문서 작성 전부터 여러 코드/데이터 변경이 있었다. 본 작업의 의도된 신규 파일은 `docs/technical/NEW_PLAN_CODE_ALIGNMENT.md` 하나다.

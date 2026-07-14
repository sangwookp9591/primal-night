# PRIMAL NIGHT 1주 차 정합성 검증

- 검증일: 2026-07-13 (Asia/Seoul)
- 검증 커밋: `807b44527a2e946b10e36bee8a87ea50a2277571`
- 엔진: `/Applications/Godot.app/Contents/MacOS/Godot` → `4.7.stable.official.5b4e0cb0f`
- 범위: REVIEW-ONLY. 프로덕션 변경은 M1~M7 실험 중에만 적용했고 매 실험 직후 `git checkout -- <file>`로 원복했다.
- 결론: 목표 장면은 2회 중 1회 끝까지 재현됐지만 동일 명령의 첫 실행은 냄새 감지 전에 실패했다. 뮤테이션은 7개 중 5개만 잡았고, M3 공정성 규칙은 현재 테스트로 보호되지 않는다.

## 0. 검증 관문과 기준선

실행 명령:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --import
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit
find tests -name 'test_*.gd' -type f | wc -l
```

관측:

```text
Godot Engine v4.7.stable.official.5b4e0cb0f
Scripts 22 / Tests 122 / Passing Tests 122 / Asserts 316 / exit=0
디스크 test_*.gd: 22
headless --path . --quit: exit=0, 파싱 오류 0
```

`--import`를 각 기준선/뮤테이션 GUT 실행 전에 선행했다. 모든 뮤테이션 실행에서 GUT 요약의 `Scripts 22 / Tests 122`를 확인했으므로, “파싱 실패한 테스트가 조용히 수집에서 빠져서 초록불”인 경우와 실제 미검출을 구분했다. 로컬 명령은 `gut.xml`을 생성하지 않았지만, stdout의 수집 스크립트 수 22를 디스크의 22개와 직접 대조했다.

GUT 출력 중 `Missing item data: plutonium`은 `test_unknown_item_is_rejected`가 `assert_push_error`로 요구한 expected error이며 실패가 아니다.

## 1. 목표 장면 E2E 재현

실행 명령(동일 명령 2회):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s scripts/creature/goal_scene_replay.gd
```

### 1.1 성공 실행에서 화살표별 관측

| 단계 | 실제 관측 근거 | 판정 |
|---|---|---|
| 플레이어가 다친다 | `[t=3.0s] player health=75 bleeding=true` | 재현 |
| 출혈로 피 냄새가 발생한다 | `[t=3.0s] bleeding_started`; active cells가 `0 → 3 → 4 → 6`으로 증가 | 재현 |
| 냄새가 바람을 타고 퍼진다 | 시작 로그 `wind=(-0.57, 0.82) strength=1.0`; 랩터 위치의 냄새가 `0.00 → 4.61 → 12.93`으로 증가. 실제 이류는 `scripts/senses/smell_grid.gd:164-198`의 wind offset과 이동분 계산을 통과한다. | 재현 |
| 랩터가 배회에서 냄새를 감지해 조사로 전환한다 | `[t=7.2s] state wander -> investigate`, 직전 `smell@raptor=12.93`, threshold `8.0` | 재현 |
| 냄새를 거슬러 접근한다 | investigate 중 플레이어 거리 `491 → 455 → 418 → 380 → 343 → 306 → 269 → 233 → 203 → 183` | 재현 |
| 추격한다 | `[t=22.9s] state investigate -> chase`; `chase_started` 신호도 관측 | 재현 |
| 플레이어가 모닥불 반경으로 도망친다 | 실제 이동 입력 경로 `218프레임`; `campfire_lit ... radius 220`; 플레이어-불 거리 `22` | 재현 |
| 랩터가 추격을 포기하고 물러난다 | `[t=26.6s] state chase -> flee`; 랩터-불 거리 `66 → 177` | 재현 |

성공 실행의 최종 출력:

```text
상태 전환 순서: [&"investigate", &"chase", &"flee"]
PerfMonitor ai avg 0.046 ms, scent avg 0.022 ms
=== 목표 장면 재현 성공 ===
exit=0
```

### 1.2 실패 실행

같은 커밋, 같은 명령의 첫 실행에서는 랩터가 냄새 띠에서 멀어지는 방향으로 배회했다.

```text
[t=3.0s] raptor=(-894, 825), state=wander
[t=7.0s] smell@raptor=0.83
[t=8.0s] smell@raptor=2.12
[t=23.0s..42.0s] raptor=(-910, 1402), smell@raptor=0.00, state=wander
[t=43.0s] === 재현 실패: 랩터가 조사로 전환하지 않았다 ===
exit=1
```

따라서 “목표 장면을 실제로 한 번 재현했는가”는 **예**지만, 반복 가능한 1주 차 검증 관문으로는 **아니오**다. 아래 B-01로 차단한다.

## 2. 테스트 신뢰성 감사 — 뮤테이션 검증

공통 절차:

1. `apply_patch`로 아래 한 가지 결함만 프로덕션 코드에 삽입.
2. `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 실행, exit 0 및 수집 가능 여부 확인.
3. 전체 GUT 22 scripts / 122 tests 실행.
4. `git checkout -- <mutated-file>`로 즉시 복구.
5. `git diff --exit-code -- <mutated-file>`로 복구 확인.

| ID | 독립 뮤테이션 | 전체 스위트 결과 | 잡힘 |
|---|---|---|---|
| M1 | `smell_grid.gd:183,188`에서 `decay_factor` 제거 | exit 1, 120/122 통과. `test_smell_decays_each_tick`, `test_smell_fades_out_and_cell_deactivates` 실패 | 예 |
| M2 | `smell_grid.gd:167-168`을 `wind_offset = Vector2i.RIGHT`로 고정해 방향 무시 | exit 0, 122/122, 316 asserts | **아니오** |
| M3 | `raptor.gd:_ai_tick`에서 INVESTIGATE 중 매 틱 `move_target = player.global_position`으로 실시간 좌표 직접 참조 | exit 0, 122/122, 316 asserts | **아니오** |
| M4 | `raptor.gd:_is_protected_by_fire`의 `>= 0`을 `< 0`으로 반전 | exit 1, 114/122 통과, 8 tests 실패 | 예 |
| M5 | 인벤토리가 가득 차도 `_slots.append(overflow_slot)`하도록 슬롯 상한 제거 | exit 1, 118/122 통과, 4 tests 실패 | 예 |
| M6 | `HealTarget.interact`에서 `_player.health.stop_bleeding()` 제거 | exit 1, 119/122 통과, 3 tests 실패 | 예 |
| M7 | `StaminaComponent.can_run()`이 항상 `true`를 반환 | exit 1, 117/122 통과, 5 tests 실패 | 예 |

### M1 상세 근거

```text
test_smell_decays_each_tick: got 60.0, expected 48.0
test_smell_fades_out_and_cell_deactivates: got 60.0, expected 0.0
Scripts 22 / Tests 122 / Passing 120 / Failing 2 / Asserts 313/316
```

### M2 상세 근거 — 테스트 구멍

현재 이류 테스트는 `tests/senses/test_smell_grid.gd:92-107`에서 바람을 `Vector2.RIGHT`로만 설정한다. 따라서 프로덕션이 모든 바람을 오른쪽으로 취급해도 그대로 통과했다.

필요한 테스트: LEFT/UP/DOWN 및 최소 한 대각선에 대해 각 방향의 downwind 셀은 증가하고 반대 셀은 0인지 매개변수화해 검증한다. F6 테스트는 속성 회전만 확인하지 말고 회전 후 실제 이류 방향까지 확인해야 한다.

### M3 상세 근거 — 공정성 규칙 테스트 구멍

뮤테이션은 소리 발신자 인자를 저장하는 정도가 아니라, 실제 `player` 그룹 노드의 실시간 좌표를 INVESTIGATE 매 틱 목표로 덮어썼다. 그런데 전체 122개 테스트가 모두 통과했다.

기존 `tests/creature/test_raptor_hearing.gd:55-68`은 player가 아닌 일반 `Node2D` source를 움직인다. `tests/creature/test_raptor_states.gd:120-133`은 시야 상실로 INVESTIGATE에 진입한 직후까지만 확인하고, 다음 INVESTIGATE 틱에서 플레이어가 다시 움직였을 때 목표가 고정되는지는 확인하지 않는다.

필요한 테스트: 실제 `player` 그룹 노드를 sight 밖에 둔 채 소리를 내고, 조사 상태 진입 후 플레이어를 여러 번 이동시키며 추가 `_ai_tick()`을 호출해 `move_target == 최초 소리 위치`가 계속 유지되는지 검증한다. 냄새 조사도 player 이동과 무관하게 오직 격자 경사 한 셀만 따라가는지 별도로 확인해야 한다.

### M4~M7 상세 근거

```text
M4: test_raptor_fire/state/scene 계열 8 tests 실패
M5: test_inventory + test_world_item_pickup 계열 4 tests 실패
M6: completed_hold / stops_blood_smell / self_bandage 3 tests 실패
M7: player speed/noise + stamina zero/exhaustion 5 tests 실패
```

### 원복과 최종 GREEN

모든 실험 후 실행:

```sh
git diff --exit-code -- scripts/senses/smell_grid.gd scripts/creature/raptor.gd scripts/inventory/inventory.gd scripts/survival/heal_target.gd scripts/survival/stamina_component.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --import
/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
git status --short
```

관측: 프로덕션 diff 0, 최종 GUT `22 / 122 / 316`, 실패 0. 리포트 생성 전 `git status --short`는 빈 출력이었고, 리포트 생성 후에는 이 파일만 변경 상태다.

## 3. TDD 준수 감사

실행 명령:

```sh
git log --reverse --format='%h %s' --shortstat 5bcb9f7^..HEAD
git show --format=fuller --no-patch 91f001d c8fb052 d46bd80 c031406 b899d34 8743cf7 807b445
rg --files-without-match 'assert_[A-Za-z_]+' tests --glob 'test_*.gd'
rg -n 'skip|pending|ignore_test|@ignore|#\s*func test_|assert_true\(true\)|assert_false\(false\)' tests --glob 'test_*.gd'
```

관측:

- 구현과 해당 테스트는 대체로 같은 기능 커밋에 들어왔다. 구현 이후 별도의 “테스트 몰아넣기” 커밋은 발견하지 못했다.
- 작업은 체력/스태미나/인벤토리/상호작용/모닥불/HUD/냄새/청각/상태/불 회피/씬 통합/디버그 표시로 분리돼 있고, 하나의 거대 단일 완료 커밋은 아니다.
- 다만 같은 커밋만으로는 test-first 작성 순서를 증명할 수 없다. T2 계열 커밋 본문은 RED/GREEN 개수를 주장하지만 원시 실행 출력은 저장소에 없다.
- T4 핵심 커밋 `c8fb052`, `d46bd80`, `c031406`, `b899d34`, `8743cf7`은 테스트와 구현이 같은 커밋에 있으나 본문에는 외부 세션 링크만 있고 RED/GREEN 출력이 없다. 저장소와 git 기록만으로 TDD 순서는 **미검증**이다.
- `91f001d` 본문은 “DebugHurt는 구현을 먼저 써버려서 테스트가 처음부터 통과했다”고 명시한다. 구현을 제거해 사후 RED를 만든 것은 최초 test-first가 아니므로 TDD 위반이다.
- 22개 test 파일 중 assert가 전혀 없는 파일은 0개다. skip/pending/주석 처리된 test/`assert_true(true)`/`assert_false(false)` 패턴은 0건이다. 실제 실행은 122 tests / 316 asserts다.

## 4. 가짜 구현 검사

실행 명령:

```sh
rg -n 'TODO|FIXME|HACK|^\s*pass\s*$|assert_true\(true\)|assert_false\(false\)|#\s*func test_|\bskip\b|\bpending\b' scripts scenes tools tests --glob '*.gd' --glob '*.tscn' --glob '*.tres'
rg -n '^\s*(pass|return\s+(true|false|null|0|""|\{\}|\[\]))\s*$' scripts scenes tools --glob '*.gd'
```

관측:

- TODO/FIXME/HACK/pass/주석 처리된 테스트/항상 참 단언: 0건.
- 상수 반환 후보는 문맥을 전수 확인했다. 파일 쓰기 성공, 입력 토글 처리, 인벤토리 제거 성공, 목표 장면 대기 성공 같은 정상 제어 흐름이며 임시 성공 반환은 발견하지 못했다.
- 냄새는 표시 전용이 아니다. `scripts/creature/raptor.gd:156-158,195-207`에서 임계치와 격자 경사가 실제 INVESTIGATE 상태 및 목표를 바꾼다.
- 소리도 표시 전용이 아니다. `scripts/creature/raptor.gd:284-307`에서 위치/반경/벽 차폐를 처리해 `_last_heard_position`을 만들고, `:153-155`에서 실제 INVESTIGATE 목표로 쓴다.
- 성공 E2E에서 실제 상태가 `wander → investigate → chase → flee`로 바뀌고 랩터 위치가 플레이어 쪽으로 이동했다. 단순 디버그 표시가 아니다.
- 아이템 HUD는 `scenes/ui/hud/hud.gd:97-108`에서 `GameData.get_item()`의 `ItemData.display_name`과 슬롯 count를 사용한다. `tests/survival/test_hud.gd`의 데이터 이름 변경 테스트도 기준선에서 통과했다.
- 무기 설명 UI/런타임 무기 데이터는 현재 저장소에 존재하지 않아 무기 수치 동일 출처 여부는 **미검증**으로 분리한다.
- `DebugHurt`와 F키 디버그 기능은 1주 차 재현용으로 실제 main scene에 있다. 가짜 구현은 아니지만 출시 승인 전 제거/비활성화 대상이다.

## 5. 고정 스택 및 성능 규칙 감사

### 5.1 준수 확인

| 항목 | 실제 근거 | 판정 |
|---|---|---|
| Godot 4.7 stable | 엔진 출력 `4.7.stable.official`; `project.godot:11`에 feature `4.7` | 준수 |
| Compatibility | `project.godot:69` `renderer/rendering_method="gl_compatibility"` | 준수 |
| typed GDScript | `scripts/`, `scenes/`, `tools/`에서 타입 없는 `var name = ...` 패턴 0건; 함수 인자/반환 시그니처 전수 출력에서 타입 누락 0건 | 준수 |
| C# 혼용 금지 | `.cs/.csproj/.sln` 0개 | 준수 |
| TileMapLayer | `scenes/world/test_world.tscn:35,40,45`가 Ground/Collision/Occlusion `TileMapLayer`; 구형 `TileMap` 0건 | 준수 |
| Navigation | `test_world.tscn:51` `NavigationRegion2D`; `raptor.tscn:27` `NavigationAgent2D` | 준수 |
| 냄새 규모 | `cell_size=128`, `tick_interval=0.25`(4Hz), 활성 셀만 순회; 기본 영역은 약 20×12=240셀 | 준수 |
| 소리 규모 | 실제 판단은 이벤트 즉시 전달이며 상시 소리 노드/큐 없음; debug marker는 `MAX_MARKERS=16` | 현재 규모 준수 |
| 공룡 규모 | main scene 랩터 1마리, 실제 navigation 추격 1마리 | 24/12 상한 이내 |

### 5.2 매 프레임 금지 항목

프로덕션 상호작용 홀드 경로에서 위반 1건을 확인했다. `Interactor._process()`가 홀드 중 매 프레임 `_prompt_of(current_target)`를 호출하고(`scripts/survival/interactor.gd:35-43`), HealTarget/CampfireSite의 `get_prompt()`는 매번 `/root/GameData`를 탐색하고 문자열을 포맷한다(`scripts/survival/heal_target.gd:28-33`, `scripts/props/campfire_site.gd:28-38`). M-03으로 기록한다.

디버그 PerformanceOverlay는 `_process()`에서 0.25초마다 새 PackedArray/Dictionary를 만들고 정렬하며 문자열을 조립한다(`scripts/debug/performance_overlay.gd:30-32,54-90`; `scripts/debug/frame_metrics.gd:13-48`). 출시 빌드에서는 `_ready()`가 processing을 끄지만, 디버그 벤치마크 자체를 교란할 수 있어 m-01로 기록한다.

그 외 `_process/_physics_process`의 동적 resource load, 파일 I/O, JSON, 매 프레임 전체 노드 검색은 발견하지 못했다. Player/Raptor/SmellGrid의 root/group 검색은 초기 캐시 또는 낮은 주기 AI tick의 cache miss에 제한된다.

## 6. 이슈 목록

### B-01. 목표 장면 재현 도구가 같은 커밋/명령에서 비결정적으로 실패

- 심각도: **BLOCKER**
- 재현 절차: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s scripts/creature/goal_scene_replay.gd`를 원복된 같은 HEAD에서 2회 실행.
- 기대: 고정 재현 도구는 매 실행 `investigate → chase → flee`, exit 0.
- 실제: 첫 실행은 43초에 `랩터가 조사로 전환하지 않았다`, exit 1. 두 번째는 전 구간 성공, exit 0.
- 근거: 첫 실행에서 랩터가 `(-910,1402)`까지 임의 배회해 냄새 농도 0인 곳에 정지. `scripts/creature/raptor.gd:45-53,213-216`은 RNG를 `randomize()`하고, 재현 도구는 seed를 고정하지 않는다.
- 권고 수정: 재현 도구가 씬 인스턴스 생성 직후 랩터 RNG를 고정 seed로 설정하고, 해당 seed로 전체 장면이 연속 반복 통과하는 GUT/CI 관문을 둔다. 임의 재시도 성공을 통과로 보지 않는다.

### B-02. M3 플레이어 실시간 좌표 추적 공정성 위반을 테스트가 놓침

- 심각도: **BLOCKER**
- 재현 절차: `Raptor._ai_tick()`에 INVESTIGATE 상태일 때 `move_target = player.global_position`을 삽입 → `--import` → 전체 GUT 실행.
- 기대: 설계서 5.3을 보호하는 테스트가 실패.
- 실제: 22 scripts / 122 tests / 316 asserts 모두 통과, exit 0.
- 근거: `tests/creature/test_raptor_hearing.gd:55-68`은 실제 player가 아닌 일반 source만 이동한다. `tests/creature/test_raptor_states.gd:120-133`은 INVESTIGATE 진입 다음 틱의 live-player 재추적을 검사하지 않는다.
- 권고 수정: 실제 player-group 노드가 마지막 소리 위치에서 이동한 뒤 여러 조사 틱을 진행해도 목표가 최초 위치에 고정되는 테스트를 추가하고, 냄새 조사 목표도 player 좌표와 독립임을 검증한다.

### M-01. M2 바람 방향 무시를 테스트가 놓침

- 심각도: **MAJOR**
- 재현 절차: wind offset 계산을 `Vector2i.RIGHT`로 고정 → `--import` → 전체 GUT 실행.
- 기대: 바람 방향별 이류 테스트 실패.
- 실제: 122/122 통과, exit 0.
- 근거: `tests/senses/test_smell_grid.gd:92-107`이 RIGHT만 검증한다. 속성 회전 테스트는 실제 이류 결과를 검사하지 않는다.
- 권고 수정: 4방향+대각선의 downwind/upwind 셀을 검증하는 매개변수 테스트 추가.

### M-02. TDD 순서를 git 기록으로 입증할 수 없고 구현-first 위반 1건이 명시됨

- 심각도: **MAJOR**
- 재현 절차: `git show --format=fuller --no-patch 91f001d c8fb052 d46bd80 c031406 b899d34 8743cf7 807b445`.
- 기대: 핵심 로직별 test-first RED 출력 또는 테스트 선행 커밋, 이후 GREEN 구현.
- 실제: 관련 테스트와 구현은 같은 커밋이라 순서를 증명하지 못한다. `91f001d`는 구현을 먼저 써서 테스트가 처음부터 통과했다고 명시한다. T4 핵심 커밋은 RED/GREEN 근거 대신 외부 세션 링크만 남긴다.
- 근거: 위 커밋 본문과 shortstat. 구현 이후 별도의 테스트 몰아넣기는 없고 기능별 커밋 분리는 양호하지만, test-first 증거는 저장소에 없다.
- 권고 수정: 이후 비자명 로직은 실패 테스트를 별도 선행 커밋 또는 CI artifact로 남기고, GREEN 커밋이 그 test만 통과시키는 구조로 기록한다.

### M-03. 상호작용 홀드 중 매 프레임 노드 탐색과 문자열 포맷

- 심각도: **MAJOR**
- 재현 절차: `rg -n 'func _process|get_node|% \[' scripts/survival scripts/props` 후 `Interactor._process → _prompt_of → get_prompt` 호출 경로 확인.
- 기대: 성능 문서 6.1에 따라 노드 참조와 prompt 문자열을 이벤트 시작 시 1회 만들고 재사용.
- 실제: 홀드 중 매 프레임 `GameData` root lookup과 `%` 문자열 포맷을 실행.
- 근거: `scripts/survival/interactor.gd:35-43,106-109`; `scripts/survival/heal_target.gd:28-33`; `scripts/props/campfire_site.gd:28-38`.
- 권고 수정: `begin()`에서 prompt를 한 번 캐시하고 `_process()`에서는 ratio와 캐시 문자열만 발신한다. GameData 참조도 `_ready()`에서 캐시한다.

### m-01. 디버그 성능 오버레이가 측정 중 반복 할당·정렬·문자열 조립

- 심각도: **MINOR**
- 재현 절차: `rg -n 'func _process|duplicate|sort|PackedStringArray|% \[' scripts/debug` 및 호출 경로 확인.
- 기대: 성능 계측 오버레이가 측정 대상에 큰 주기성 할당/정렬을 추가하지 않음.
- 실제: 0.25초마다 sample 배열 생성, duplicate+sort, 중첩 Dictionary 반환, 문자열 포맷을 수행.
- 근거: `scripts/debug/performance_overlay.gd:30-32,54-90`; `scripts/debug/frame_metrics.gd:13-48`.
- 권고 수정: 표시가 켜진 경우에만 저빈도 갱신하고, 측정용 원시 ring buffer 집계와 UI용 정렬/문자열 생성을 분리한다. 출시 빌드 비활성화는 현재 정상이다.

## 7. 미검증 항목

- Windows 10/11 물리 장비, Standard/Compatibility 실제 GPU 출력, Windows export 실행은 이 macOS headless 감사에서 실행하지 못했다.
- F4/F6/F7 디버그 표시의 실제 화면 픽셀은 headless에서 시각 확인하지 못했다. 토글/데이터 테스트는 통과했다.
- 무기 설명 UI와 무기 런타임 데이터는 아직 존재하지 않아 동일 출처 여부를 확인할 대상이 없다.
- 2인 접속은 명시적으로 2주 차 범위라 실행하지 않았다.
- 성능 문서의 24마리/12추격 최대 부하 자체는 현재 콘텐츠가 랩터 1마리라 실행할 수 없었다. 현재 씬이 상한 이내인 사실만 확인했다.

## 8. 최종 요약

- 목표 장면 재현 성공 여부: **예 — 2회 중 1회 성공. 단, 반복 신뢰성 관문은 실패(B-01).**
- 뮤테이션 검출: **5/7**
- 놓친 뮤테이션: **M2, M3**
- 최종 정상 스위트: **22 scripts / 122 tests / 122 pass / 316 asserts**
- 최종 headless 파싱: **exit 0, 오류 0**
- BLOCKER: **2**
- MAJOR: **3**
- MINOR: **1**
- 프로덕션 원복: **완료. 리포트 외 변경 없음.**

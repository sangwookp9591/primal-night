# PRIMAL NIGHT 1주 차 최종 관문 재검증 (Round 2)

- 검증일: 2026-07-13 (Asia/Seoul)
- 검증 HEAD: `b7f4f6918fe7a11a037f658c4d76e6abc8441ba6`
- 엔진: Godot `4.7.stable.official.5b4e0cb0f`
- 범위: **REVIEW-ONLY**. 영구 프로덕션 변경 없음. 모든 mutation은 개별로 심고 `git checkout -- <file>`로 즉시 원복했다.
- 정본: `docs/superpowers/specs/2026-07-13-primal-night-design.md`, `docs/technical/2026-07-13-performance-budget-and-regression-policy.md`

## 0. 결론

- 뮤테이션 검출: **7/7**
- 목표 장면 결정성: **10/10**
- BLOCKER 잔존: **0건**
- 게임 플레이의 무작위성이 훼손됐는가: **아니오**
- **2주 차(Steam 멀티플레이) 착수 가능: 가능.** 로컬 기반은 최종 GUT 128/128, mutation 7/7, 실제 목표 장면 10/10으로 안정성을 보였다. 단, 설계서 16.2에 따라 2주 말 원격 2인 이동·상호작용이 안정적임이 증명되기 전에 추가 멀티플레이 기능을 쌓는 것은 승인하지 않는다.

중요 단서 하나가 있다. `test_goal_scene_arc` 는 상태 아크와 냄새 경사 추적을 검증하지만, 냄새 띠를 직접 주입하므로 **실제 이류/감쇠 전파의 독립 CI 관문은 아니다**. 이는 MAJOR 테스트 경계 결함으로 남기되, 전용 냄새 테스트가 전파 중단 mutation을 실제로 검출하고 목표 장면 replay가 10/10 통과했으므로 현재 런타임 BLOCKER로는 판정하지 않았다.

## 1. 기준선과 조용한 스킵 방지

모든 GUT 실행 직전에 다음 import를 선행했다.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit \
  -gjunit_xml_file=res://artifacts/gut.xml
```

매 실행에서 `artifacts/gut.xml`의 `<testsuite>` 24개와 `find tests -name 'test_*.gd' -type f` 24개를 대조했다. 모든 mutation에서 24=24였으므로 파싱 실패 테스트가 수집에서 조용히 빠져 위양성이 된 경우는 없다.

최종 원복 기준선:

```text
import exit=0
GUT exit=0
Scripts 24 / Tests 128 / Passing 128 / Asserts 362 / Failing 0
gut.xml testsuites=24, tests=128, failures=0
디스크 test_*.gd=24
headless --path . --quit exit=0
```

`Missing item data: plutonium`은 `test_unknown_item_is_rejected`가 `assert_push_error` 로 요구하는 expected error이며 실패가 아니다.

## 2. 뮤테이션 검증

| ID | 독립 mutation | GUT 결과 | 실패 테스트 | 검출 |
|---|---|---|---|---|
| M1 | `SmellGrid._tick()`에서 잔류분·이동분의 `decay_factor` 제거 | exit 1, 125/128, 343/362, JUnit 24/24 | `test_smell_decays_each_tick`, `test_smell_fades_out_and_cell_deactivates`, `test_wind_advects_downwind_for_every_direction` | 예 |
| M2 | wind offset을 `Vector2i.RIGHT`로 고정 | T8: exit 1, 127/128, 354/362, JUnit 24/24 | `test_wind_advects_downwind_for_every_direction` | 예 |
| M3 | INVESTIGATE에서 실시간 `player.global_position`으로 목표 덮어쓰기 | T8: exit 1, 125/128, 355/362, JUnit 24/24 | `test_investigation_stays_on_first_heard_position_while_real_player_moves`, `test_smell_investigation_target_is_independent_of_player_position`, `test_losing_sight_downgrades_to_investigating_last_seen_position` | 예 |
| M4 | `_is_protected_by_fire()`의 `>= 0`을 `< 0`으로 반전 | exit 1, 119/128, 348/362, JUnit 24/24 | 아래 9개 | 예 |
| M5 | 용량이 찼 뒤에도 `_slots.append(overflow_slot)` | exit 1, 124/128, 352/362, JUnit 24/24 | 아래 4개 | 예 |
| M6 | `HealTarget.interact()`의 `stop_bleeding()` 제거 | exit 1, 125/128, 358/362, JUnit 24/24 | 아래 3개 | 예 |
| M7 | `StaminaComponent.can_run()`이 항상 `true` | exit 1, 123/128, 357/362, JUnit 24/24 | 아래 5개 | 예 |

M4 실패 테스트 9개:

- `test_goal_scene_arc_investigate_chase_flee_with_fixed_seed`
- `test_chase_is_abandoned_when_player_reaches_the_fire`
- `test_flee_ends_outside_the_exit_radius`
- `test_extinguished_fire_no_longer_protects_the_player`
- `test_alert_mark_shows_on_chase_and_fades`
- `test_seeing_player_triggers_chase_with_perceivable_alert`
- `test_chase_tracks_player_while_perceived`
- `test_losing_sight_downgrades_to_investigating_last_seen_position`
- `test_sight_hysteresis_keeps_chase_between_radii`

M5 실패 테스트 4개:

- `test_rejects_items_beyond_slot_capacity`
- `test_partial_add_when_only_some_room_left`
- `test_pickup_rejected_when_inventory_is_full`
- `test_partial_pickup_leaves_the_remainder_in_the_world`

M6 실패 테스트 3개:

- `test_completed_hold_stops_bleeding_and_consumes_the_bandage`
- `test_healing_stops_the_blood_smell`
- `test_player_can_bandage_themselves`

M7 실패 테스트 5개:

- `test_exhausted_player_moves_at_walk_speed_even_while_holding_run`
- `test_exhausted_player_emits_walk_noise_not_run_noise`
- `test_cannot_run_at_zero_stamina`
- `test_exhaustion_locks_running_until_threshold_recovered`
- `test_exhausted_run_input_does_not_drain_further`

따라서 T5의 “M1/M4~M7이 전부 검출된다”는 주장은 Round 2에서 독립 재현됐다. T8에서 다시 심은 M2/M3까지 합치면 **7/7**이다.

## 3. B-01 목표 장면 결정성

### 3.1 실제 replay 10회

import 후 다음 명령을 동일 HEAD에서 연속 10회 실행했다.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s scripts/creature/goal_scene_replay.gd
```

| Run | exit | 상태 순서 | 결과 |
|---:|---:|---|---|
| 1~10 | 모두 0 | `investigate → chase → flee` | 모두 `=== 목표 장면 재현 성공 ===` |

전환 좌표와 목표는 10회 모두 같았다.

```text
wander -> investigate: raptor=(-884,755), target=(-794,665)
investigate -> chase:  raptor=(-477,348), target=(-384,200)
chase -> flee:         raptor=(-246,294), target=(-467,153)
```

단, 로그의 프레임 기반 시각은 바이트 단위로 같지 않았다. 실행별로 `wander→investigate` 20.2~20.3초, `investigate→chase` 42.2~42.3초, `chase→flee` 45.9~46.0초의 최대 0.1초 차이가 있었다. 상태 순서·좌표·목표·종료 코드는 같았으므로 게임 결과의 결정성은 10/10으로 판정한다.

### 3.2 게임 플레이 무작위성

무작위성은 훼손되지 않았다.

- 프로덕션 `Raptor._ready()`는 `scripts/creature/raptor.gd:53`에서 매 인스턴스의 `rng.randomize()`를 호출한다.
- 고정 seed는 장면 인스턴스 생성 **후** `scripts/creature/goal_scene_replay.gd:34`에서 replay의 랩터에만 주입된다.
- GUT는 `tests/creature/test_goal_scene_arc.gd:44`, 기존 랩터 이동 테스트는 `tests/creature/test_raptor_scene.gd:50`에서만 seed를 고정한다.
- 프로덕션 스크립트에 상수 seed 대입은 없다.

### 3.3 `test_goal_scene_arc`의 관문 강도

실제 전파를 끊기 위해 `SmellGrid._tick()` 첫 줄에 임시 `return`을 심었다. import 후 전체 GUT 결과는 exit 1, 124/128, 341/362였고 JUnit 24/24였다.

- 실패: `test_smell_decays_each_tick`, `test_smell_fades_out_and_cell_deactivates`, `test_wind_advects_smell_downwind`, `test_wind_advects_downwind_for_every_direction`
- **통과:** `test_goal_scene_arc_investigate_chase_flee_with_fixed_seed`

원인은 `tests/creature/test_goal_scene_arc.gd:55-59`가 바람이 만든 결과물을 시뮬레이션하지 않고 다섯 셀에 직접 `smell_emitted` 하는 것이다. 따라서 이 테스트는 “이미 형성된 냄새 경사를 랩터가 거슬러 올라가 chase/flee로 전환한다”는 상태 아크 관문이지, 실제 이류/감쇠 통합 관문은 아니다. 다만 전체 CI에서는 전용 냄새 테스트들이 이 mutation을 잡는다.

## 4. 성능 수정 검증

### 4.1 M-03 홀드 상호작

현재 호출 경로:

```text
Interactor.begin()
  -> find_target()                         # 키 입력 시 1회
  -> _hold_prompt = _prompt_of(target)     # 홀드 시작 시 1회
     -> HealTarget/CampfireSite.get_prompt()
Interactor._process()
  -> hold_changed.emit(..., _hold_prompt)  # 캐시 문자열만 사용
```

- `scripts/survival/interactor.gd:36-49`의 `_process()`에는 `get_node`, `find_child`, 문자열 `%` 포맷이 없다.
- 프롬프트는 `interactor.gd:68`에서 시작 시 1회 생성되고 `:43`에서 그대로 재사용된다.
- `HealTarget`/`CampfireSite`의 `/root/GameData` 탐색은 각각 `_ready()` (`heal_target.gd:15-17`, `campfire_site.gd:15-16`)에서 1회 캐시된다.
- `%` 포맷은 `get_prompt()`에 남아 있지만 `_process()`가 아니라 홀드 시작 이벤트에서만 실행된다.

`test_hold_prompt_is_read_once_at_begin_and_reused_during_process` 는 껍데기가 아니다. 카운팅 테스트 더블의 `get_prompt()` 호출 횟수를 늘린 후 `begin + _process 3회`에서 `prompt_reads == 1`과 label 시퀀스 4개가 모두 `"cached prompt"`임을 단언한다 (`tests/survival/test_interactor_prompt_cache.gd:47-53`).

게임 동작은 유지됐다. 프롬프트 텍스트는 같은 `ItemData.display_name`/비용 Resource에서 생성되고, 첫 `hold_changed(0.0, label)`과 이후 progress emit, 완료 타이밍은 변하지 않았다. 실제 프롬프트 자료는 홀드 중 변하지 않는 정적 item/config 데이터이다.

### 4.2 m-01 성능 오버레이

- 릴리스 빌드는 `_ready()`에서 `set_process(false)`한다 (`performance_overlay.gd:17-21`).
- 디버그에서 F3으로 끄면 `set_process(false)`가 적용된다 (`:41-49`).
- 엔진이 `_process()`를 호출하지 않고, 직접 호출해도 `:32-34`의 guard가 즉시 반환한다.
- `test_hidden_overlay_does_not_record_or_refresh_in_process` 는 숨긴 뒤 `_process(1.0)`을 직접 호출해 sample count 0, refresh elapsed 0.0을 검증한다.

따라서 오버레이가 꺼진 상태의 프레임 갱신 비용은 0이다. 다만 디버그 오버레이가 켜져 있을 때의 표시 갱신 주기는 0.25초에서 1.0초로 느려졌다. 이는 의도된 진단 UI 변경이며 플레이어 규칙·상호작·HUD 타이밍을 바꾸지 않는다.

## 5. 늘어난 6개 테스트와 가짜 구현 검사

122→128을 만든 신규 테스트는 정확히 6개다.

| 테스트 | 실제 검증 | 판정 |
|---|---|---|
| `test_hold_prompt_is_read_once_at_begin_and_reused_during_process` | 호출 횟수 1과 신호 label 시퀀스 | 유효 |
| `test_hidden_overlay_does_not_record_or_refresh_in_process` | 숨김 직접 `_process` 후 sample/refresh 0 | 유효 |
| `test_wind_advects_downwind_for_every_direction` | 4방향+대각선 4방향의 downwind/upwind/잔류분 | 유효, M2 검출 |
| `test_investigation_stays_on_first_heard_position_while_real_player_moves` | 실제 player-group node의 3회 이동 후 첫 소리 위치 고정 | 유효, M3 검출 |
| `test_smell_investigation_target_is_independent_of_player_position` | 냄새 경사 목표와 player 실시간 좌표 분리 | 유효, M3 검출 |
| `test_goal_scene_arc_investigate_chase_flee_with_fixed_seed` | 고정 seed 상태 순서, 경사 추적, chase, fire flee | 부분 유효; 실제 전파는 미검증 |

스캔 결과:

```sh
git diff 807b445..HEAD -- tests | rg '^\+func test_'
rg --files-without-match 'assert_[A-Za-z_]+' tests --glob 'test_*.gd'
rg -n 'TODO|FIXME|HACK|^\s*pass\s*$|assert_true\(true\)|assert_false\(false\)|#\s*func test_|\bskip\b|\bpending\b' \
  scripts scenes tools tests --glob '*.gd' --glob '*.tscn' --glob '*.tres'
rg -n '^\s*(return\s+(true|false|null|0|""|\{\}|\[\])|pass)\s*$' \
  scripts scenes tools --glob '*.gd' --glob '*.tscn' --glob '*.tres'
```

- 신규 test function: 6개. 모두 구체적 단언이 있다.
- assert가 하나도 없는 `test_*.gd`: 0개.
- `assert_true(true)`, `assert_false(false)`, skip/pending, 주석 처리된 test: 0건.
- TODO/FIXME/HACK/독립 `pass`: 0건.
- 상수 반환 후보는 파일 기록 성공, 입력 토글, 인벤토리 제거 성공, 기대된 거부·빈 표시 스트링으로 모두 정상 제어 흐름이다. 새로 추가된 `return true` 1건은 테스트 더블 `CountingPromptTarget.can_interact()`의 전제이며 프로덕션 임시 성공이 아니다.
- 신규 빈 callback·주석 처리된 핵심 로직은 0건이다.

## 6. 잔존 이슈

### R2-M-01. `test_goal_scene_arc`는 실제 냄새 전파 통합 관문이 아님

- 심각도: **MAJOR**
- 재현: `SmellGrid._tick()` 즉시 `return` → import → 전체 GUT.
- 실제: 냄새 테스트 4개는 실패하지만 `test_goal_scene_arc` 는 통과.
- 영향: 테스트 이름/주석을 전파 포함 E2E로 읽으면 보호 범위를 과대평가한다.
- 권고: 현 테스트를 “상태 아크” 관문으로 명확히 유지하고, CI에 실제 `goal_scene_replay.gd`를 실행하거나 출혈→이류→랩터 감지를 하나의 통합 테스트로 남긴다.
- BLOCKER가 아닌 이유: 실제 replay 10/10이고, 전용 냄새 테스트가 동일 mutation을 전체 CI에서 이미 차단한다.

## 7. 원복·작업 트리 확인

모든 mutation 실행 직후 해당 파일을 `git checkout --` 했고 `git diff --exit-code -- <mutated-file>`로 원복을 확인했다. 최종적으로 다음 프로덕션 파일의 diff는 0이다.

```text
scripts/senses/smell_grid.gd
scripts/creature/raptor.gd
scripts/inventory/inventory.gd
scripts/survival/heal_target.gd
scripts/survival/stamina_component.gd
```

리포트 작성 전 `git status --short`는 빈 출력이었다. 따라서 최종 상태는 **이 리포트 파일을 제외하면 clean**이다.

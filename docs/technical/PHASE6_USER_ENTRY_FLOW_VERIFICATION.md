# Phase 6 — 유저 진입 흐름 검증

## 결과

`boot.tscn`의 GUI 실행은 Title 화면으로 들어가며, 싱글/호스트는 난이도를 고른 뒤
`main.tscn`으로 진입한다. 참가는 직접 `IP:port`만 받으며 접속 성공 뒤 main으로
진입하고 호스트가 RPC로 보낸 난이도를 적용한다. 헤드리스 boot의 조기 반환과
`main.tscn` 직접 인스턴스화 경로는 유지되며, 직접 로드는 항상 표준 난이도를 쓴다.

## 실제 난이도 연결

| 축 | 프리셋 변수 | 실제 연결 지점 |
|---|---|---|
| 자원 여유 | `resource_spawn_quantity_multiplier` | `DifficultyRuntime` → main 하위 `WorldItem.apply_spawn_quantity_multiplier`; 시드 월드 아이템 수량 |
| 흔적 가독성 | `trace_feedback_duration_multiplier`, `trace_feedback_intensity_multiplier` | `Hud.bind` → `SenseIndicatorModel`의 소리 방향 지속 시간 및 바람/소리 화살표 알파 |
| 사망 복구 | `death_item_keep_ratio` | `EventBus.damage_taken`에서 사망 확정 감지 → `Inventory.apply_death_keep_ratio`; 보존되지 않은 기존 아이템은 `world_item.tscn`으로 사망 위치에 드롭 |
| 포식자 관용도 | `raptor_investigate_threshold_multiplier`, `raptor_chase_give_up_seconds` | `Raptor.apply_difficulty` → 복제된 `CreatureData.smell_threshold`, 시야 상실 추격 유예 |

적 체력 배수는 정의하거나 적용하지 않았다.

현재 게임에는 자원 리스폰 스케줄러가 없으므로
`resource_respawn_time_multiplier`는 향후 연결을 위한 Resource 필드만 정의했고 실제
런타임에는 연결하지 않았다. 플레이어 리스폰 시스템도 없으므로 사망 복구는 현재
존재하는 인벤토리 보존/월드 드롭 범위까지만 적용한다.

프리셋:

- 온화: 자원 1.5배, 흔적 지속 1.5배/강도 1.25배, 아이템 100% 유지,
  랩터 냄새 조사 임계 1.5배, 시야 상실 유예 0.5초.
- 표준: 기존 자원/흔적/조사 임계, 아이템 50% 유지, 기존과 같은 즉시 시야 상실.
- 가혹: 자원 0.75배, 흔적 지속 0.7배/강도 0.8배, 아이템 전부 드롭,
  랩터 냄새 조사 임계 0.75배, 시야 상실 유예 2초.

## 자동 검증

Godot `4.7.1`, `HOME=/tmp`:

```sh
/opt/homebrew/bin/godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

- GUT: 87 scripts, 498 tests, 26,974 asserts, failures 0.
- `scripts/net/two_player_harness.gd`: exit 0, PASS.
- `scripts/survival/two_player_coop_harness.gd`: exit 0, PASS.
- `scripts/net/two_player_goal_scene_harness.gd`: exit 0, PASS.
- `scripts/net/four_player_equipment_harness.gd`: exit 0, host+3의 16개 아바타 일치 PASS.

기존 GUT가 보고하는 12 orphan과 하네스 종료 시 ObjectDB/resource leak 경고는
기준선과 동일한 기존 정리 경고이며 판정 실패는 아니다.

신규 테스트는 다음을 검증한다.

- 세 프리셋이 네 연결 축의 값을 실제로 다르게 만든다.
- 선택 프리셋이 실제 main의 월드 아이템 수량과 랩터 데이터에 적용된다.
- main 직접 로드는 표준을 자동 적용한다.
- 흔적 피드백 지속 계수가 실제 모델 만료 시간을 바꾼다.
- 가혹 사망 규칙이 기존 인벤토리를 월드 아이템으로 드롭한다.
- Title의 메뉴, 포커스 체인, 난이도 전환, 잘못된 참가 주소와 사람이 읽을 수 있는
  버전/네트워크 실패 문구가 동작한다.

## GUI 수동 검증 절차

1. `/opt/homebrew/bin/godot --path .`를 실행한다.
2. Title에서 마우스로 싱글 시작 → 온화 → 플레이를 선택하고 main 진입을 확인한다.
3. 다시 실행해 키보드 방향키와 Enter만으로 호스트 시작 → 표준 → 플레이까지
   이동한다. 포커스가 항상 보이고 순서가 끊기지 않는지 확인한다.
4. 게임패드 D-pad/스틱과 확인 버튼만으로 Title의 네 항목, 난이도 네 항목(뒤로 포함),
   참가 주소/접속/뒤로를 모두 순회·확정한다.
5. 참가에서 잘못된 문자열을 입력해 `IP:port` 안내와 Title 잔류를 확인한다.
6. 열려 있지 않은 유효 주소(예: `127.0.0.1:6553`)로 참가해 접속 실패 문구와
   뒤로 포커스를 확인한다.
7. 두 인스턴스를 실행해 한쪽은 가혹 호스트, 다른 쪽은 `IP:port` 참가로 접속한다.
   참가자가 별도 난이도를 고르지 않고 main에 들어오는지 확인한다.
8. 창 크기 변경, 마우스, 키보드, 패드를 번갈아 사용해 버튼 클릭과 포커스 탐색이
   함께 유지되는지 확인한다.

# PRIMAL NIGHT — 세션 인수인계 문서 (Handoff)

> 갱신: 2026-07-19, 코디네이터(Fable 5) 세션 종료 시점. 이 문서 하나로 컨텍스트 없이 이어받을 수 있게 쓴다.
> 시작 명령: `/orchestration /goal docs/HANDOFF_NEXT_SESSION.md` (또는 §6 작업 큐에서 태스크를 골라 디스패치)

---

## 1. 현재 상태 스냅샷

- **HEAD**: `62222c1` (main). 작업 트리 클린. **origin과 완전 동기화** — 사용자가 매 요청마다 push를 지시해온 패턴이나, 새 커밋의 임의 push는 여전히 금지(요청 시에만).
- **테스트**: GUT **676/676 실패 0**. 하네스 전부 초록. combat '사체 복제' 플레이크는 조건 대기 전환으로 해소됨(`07c8cb9`, 18연속 PASS).
- **CI 하네스 목록** (.github/workflows/ci.yml): GUT, two_player, network_conditions, two_player_coop, two_player_goal_scene(×5), goal_scene_replay, sense_loop(10시드), three_day_slice, four_player_equipment(host+3), two_player_combat(host+1), four_player_soak(압축 0.5분).
- **export**: 템플릿 설치됨. macOS zip(부팅 스모크 OK)·Windows exe 생성 확인. `export/`는 gitignore.
- **완성된 축**: 감지 루프(냄새·바람·소리), 장비 3부작+modifier 실연결(방어·가방 용량), 창·활·횃불 전투, 3구역 절편(Z01→Z03), 세션 4결과, 난이도 3종, 저장·이어하기·사망 복구, 비·젖음·의상, 캐릭터 기록+**사망 요약 화면**(일수·거리·구역·대표 장비·타임라인), **기획안 16건 전체**(채집·독버섯·요리·물·사체 끌기·흔적 지우기·은신·귀 기울이기·투척·유인·연기·숯·기름 함정·올가미·야외 세이브), **상용화 비주얼**(줌 3.0, 밝은 타일, 시간대 색조·광원, 그림자, 파티클, 목질 UI 테마, 타이틀 아트), 캐릭터·랩터 시트 방향 규약 정합.

## 2. 정본 문서 (우선순위 순)

1. `/Users/psw/Downloads/PRIMAL_NIGHT_ZOMBOID_FUN_DIRECTION.md` — **현행 제품 방향 정본**. §6 "만들지 말 것" 준수.
2. `/Users/psw/Downloads/primitive_survival_game_plan_vs_project_zomboid.md` — **신규 비전 문서(지위 미정)**. opus 크리틱 결론: "정본 교체가 아니라 현행 방향의 3자 검증 — 2단계 비전 부록으로 편입 권고". §5.3 사망 요약은 이미 흡수됨.
3. `docs/technical/NEW_PLAN_CODE_ALIGNMENT.md` — 신규 문서 vs 코드 갭 정렬표(file:line 근거) + 충돌 4건 + 로드맵.
4. `docs/design/PROPOSAL_INTERACTIONS_ITEMS_2026-07-19.md` — 기획안(16건 전체 구현 완료 상태).
5. `docs/PRIMAL_NIGHT_GITHUB_AUDIT_AND_AGENT_LOOP.md` — 실행 루프 정본.
6. `docs/technical/DESIGN_DOC_CODE_ALIGNMENT.md` — 구 설계 문서 정렬표(반영 완료).

핵심 판단 기준: **"공룡과 싸우는 게임이 아니라, 내가 남긴 흔적 때문에 사냥당하는 게임"** + 새 문서의 "이득에는 흔적 대가" 원칙.

## 3. 모델 적재적소 배치표

| 모델 | 역할 | 맡길 일 | 맡기지 말 일 |
|---|---|---|---|
| **codex gpt-5.6-sol** | 리드 엔지니어 + 에셋 담당 | Godot/GDScript 구현, 넷코드(호스트 권위), 픽셀 에셋 생성(imagegen)·시트 규약, 회귀 디버깅 | 최종 판정, 커밋 |
| **codex gpt-5.5** | 테스트·기계적 이전·문서 | 플레이크 안정화, 문서 감사·정렬표, 반복 리팩터링, 데이터 재편 | 큰 설계 판단 |
| **opus 4.8** (claude 서브에이전트) | 냉정한 반대 검토자 | 대형 전환 크리틱(신규 비전 문서 크리틱 전례), 2단계 계획 검토 | 구현 자체 |
| **Fable 5** (코디네이터) | 오케스트레이터 + 플레이 경험 평가 | 태스크 분해·디스패치·검증·커밋 전권, GUI 실기(스크린샷 판정), 서사 문구 감수, /simplify 취합 | — |

워커 생성 명령(코디네이터가 실행):
```bash
orca terminal create --worktree active --title <이름> \
  --command "codex -m gpt-5.6-sol -s workspace-write -a never -c sandbox_workspace_write.network_access=true" --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 90000 --json
orca orchestration task-create --spec "<상세 명세>" --json
orca orchestration dispatch --task <task_id> --to <handle> --inject --json
orca orchestration check --wait --types worker_done,escalation,decision_gate --timeout-ms 580000 --json
```

## 4. 운영 수칙 (사고 이력 기반 — 어기면 재발한다)

1. **커밋·push는 코디네이터 전권.** 태스크 명세에 "git commit/push 절대 금지, 위반 시 실패 처리" 명시. worker_done 직후 `git log` 확인.
2. **워커 검증은 참고, 판정은 코디네이터 재검증.** 워커는 `HOME=/tmp`로 GUT 우회 실행. 커밋 전 코디네이터가 전체 GUT + 관련 하네스 직접 실행.
3. **간헐 실패는 통계로 판정**(전례: 랩터 속도 변경 후 combat 플레이크 7회 중 2회 → 원인 규명 후 10연속 PASS 증명 요구).
4. **같은 워크트리 병렬 워커**는 파일 영역 비겹침일 때만. 같은 파일(visual_profile, 아이템 시트)이 필요하면 순차 또는 시트 소유권을 웨이브당 한 워커에 배정. 교차 간섭으로 상대 영역 테스트가 깨져 보이면 에스컬레이션이 정상 동작(침범 금지).
5. **저장 스키마 JSON 왕복 시 int→float** — 새 int 필드는 SaveService 정규화 계층 등록. 복원 테스트는 실파일 왕복(prepare_continue 패턴) 필수 — 메모리 스냅샷 왕복만으로는 불충분.
6. **Orca 런타임 재시작 시 터미널·코디네이터 핸들 전부 무효화** — `terminal list`로 재해석. `check --wait`가 worker_done을 못 받아도 **task-list 상태가 정본**. 워커 ask가 미전달될 수 있으니 워커가 합리적 우회를 택했다면 사후 비준하고 게이트에 기록 회신.
7. **새 class_name 추가 후 GUT 대량 실패**(Identifier not declared)는 클래스 캐시 문제 — `godot --headless --path . --import` 1회로 해소.
8. **원화(source) 시트는 착의 상태** — BaseBody 재작업 시 의류 제거 필수(이중 겹침 사고 이력). 시트 규약: **열=방향 8(N,NE,E,SE,S,SW,W,NW), 행=idle 2+walk 4**, 플레이어 48x64·랩터 96x80. S열=정면 얼굴.
9. 검증 순서: 관련 GUT → 전체 GUT → 관련 하네스 → (UI/시각이면) GUI 실기. 초록이어도 재미·가독성은 별개 판정.

## 5. 검증·GUI 명령 모음

```bash
G=/opt/homebrew/bin/godot   # 4.7.1
"$G" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit  # 전체 GUT
"$G" --headless --path . --import   # class_name 캐시 재생성 (신규 클래스 후 필수)
"$G" --path . -s tools/visual_gallery.gd       # 의상·상태·방향 갤러리 (GUI, user://visual_gallery.png)
"$G" --path . -s tools/harvest_shake_probe.gd  # 흔들림 프레임 덤프 프로브 전례
```
GUI 실기: 게임 pid `frontmost` 지정 후 osascript key code(단발)/`key down`·`key up`(홀드·수식키는 `key down control`). **키 입력 전 반드시 frontmost 재확인**(포커스 뺏기면 터미널에 타이핑됨). 캡처는 `screencapture -x` 전체 후 크롭(게임 창 영역 대략 (555,385)-(2455,1475)). 시각 피드백 판정은 방황하지 말고 tools/ 프로브 스크립트(SceneTree + viewport get_image)로 결정적 검증. walk_speed 150px/s, 스폰 (-384,200), 거점: 보관함(-420,400)·건조대(-300,420)·잠자리(-180,400). 저장: `~/Library/Application Support/Godot/app_userdata/PRIMAL NIGHT/saves/slot_1.save` — 실기 전 백업, 종료 후 복원. 인벤 UI: Esc=장착 해제, 닫기=Tab, 소비는 Enter(`[Enter: 먹기]`). 성능 오버레이는 F3(기본 숨김).

## 6. 남은 작업 큐 (우선순위 순)

| # | 작업 | 담당 | 비고 |
|---|---|---|---|
| 1 | **사람 플레이테스트 실행** — docs/playtest/PLAYTEST_01_OBSERVATION_SHEET.md | **사용자**+5명 | 최우선 관문. **통과 전 신규 콘텐츠 확장 금지**. 관찰 포인트: Esc/Tab 혼동, 랩터 순찰이 너무 정적인지(배회 3초에 38px) |
| 2 | **신규 비전 문서 결정 4건** | **사용자** | ①넷코드 동결(권고) vs 삭제 ②문서 지위(2단계 부록 편입 권고) ③3일 4결과 유지(권고) vs 자유 생존 점프 ④플레이테스트 관문 유지 여부. 갭 표: NEW_PLAN_CODE_ALIGNMENT.md |
| 3 | 관찰 중 버그: 사망 요약 '발견 지역'에 미방문 Z03 기록(장거리 이동 판에서 1회, 0km 판에선 미재현) | gpt-5.5 | Chronicle 방문 구역 판정(청크→존 매핑) 재현·수정. 낮은 심각도 |
| 4 | /simplify 보류 3건: 횃불 폴링→장비 시그널 이관, SessionClock 위상 진행률 API, 멀티 피해 이펙트 중복 | gpt-5.6-sol | `62222c1` 커밋 메시지에 사유 기록. ③은 솔로 전환 결정과 함께 |
| 5 | GUI 실기 잔여: 모닥불 점화→굽기·스프, 창 제작→랩터 전투, 올가미 포획 실기 | Fable 5 | 재료 조달(사냥) 흐름 포함 — 플레이테스트 리허설을 겸함 |
| 6 | 아트 후속 후보: 랩터 사체 어두운 날개/뼈 파트, 보관함 상자 렌더, 새 캐릭터 스타일(청키 픽셀)과 장비 오버레이 톤 재정합 여부 | gpt-5.6-sol | 사용자 시각 판정 후 |
| 7 | **2단계 장기 생존 모드**(신규 비전 문서가 상세 사양) | opus 크리틱 → gpt-5.6-sol | **플레이테스트 재미 증명 + 결정 4건 확정 전 착수 금지** |

## 7. 함정 모음 (요약)

- codex 워커 플래그 없으면 worker_done·ENet 실패(`network_access=true` 필수). Godot 첫 설치 quarantine.
- 하네스는 main.tscn 직접 로드 → 저장 비활성·표준 난이도. 이 경로 판정을 깨는 변경 금지. 시간대 색조·그림자·파티클은 전부 시각 전용으로 유지할 것.
- goal_scene_replay는 랩터 속도·배회량에 민감(walk 55 기준 기대값으로 갱신됨). 속도류 튜닝 시 하네스 기대값 동반 검토.
- 난이도 메뉴 초기 포커스 '표준', 타이틀은 '싱글 시작'. 이어하기는 저장 존재 시에만.
- 아이템 시트는 29셀(0-28)·좌표 불변 계약. 새 아이템은 뒤에 추가 + world_item.gd 매핑 + test_item_sprite_mapping 동기화.
- 오케스트레이션 상태: `orca orchestration task-list --brief --json`. 이전 태스크 전부 completed.

## 8. 메모리 인덱스 (Claude 전용)

`~/.claude/projects/-Users-psw-Projects-primal-night/memory/`: `primal-night-agent-loop-progress`(1~13차 사이클 커밋 이력·교훈), `codex-orca-worker-sandbox`, `primal-night-godot-env`. 다음 세션 시작 시 갱신하며 사용할 것.

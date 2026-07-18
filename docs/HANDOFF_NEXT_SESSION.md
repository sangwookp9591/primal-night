# PRIMAL NIGHT — 세션 인수인계 문서 (Handoff)

> 작성: 2026-07-18, 직전 코디네이터(Fable 5) 세션 종료 시점.
> 대상: 다음 세션의 오케스트레이터. 이 문서 하나로 컨텍스트 없이 이어받을 수 있게 쓴다.
> 시작 명령: `/orchestration /goal docs/HANDOFF_NEXT_SESSION.md` (또는 아래 §6 작업 큐에서 태스크를 골라 디스패치)

---

## 1. 현재 상태 스냅샷

- **HEAD**: `f56dbf2` (main, 2026-07-18 5차 세션). 작업 트리 클린. origin은 `328e6ad`까지 push됨(사용자 지시) — 이후 아트 3커밋(`c8b57cf` 줌 3.0, `24c03b4` 맵 아트, `f56dbf2` 캐릭터 정합)은 미push, 사용자 결정 대기. **임의 push 금지.**
- **테스트**: GUT **586/586 실패 0**. 하네스 전부 초록. export 템플릿 설치됨(macOS zip·Windows exe 생성 확인).
- **비주얼**: 좀보이드 레퍼런스 정합 완료 — 줌 3.0(캐릭터 화면높이 ~13%), 밝은 초지 타일(이음선 없음), 식생 장식 레이어(해시 결정론·충돌 없음), 캠프 가구·청소동물 실렌더, 캐릭터 원화 정합. 아트 후속 후보: 랩터 사체 어두운 날개/뼈 파트, 보관함 상자 렌더.
- **CI 하네스 목록** (.github/workflows/ci.yml): GUT, two_player, network_conditions, two_player_coop, two_player_goal_scene(×5), goal_scene_replay, sense_loop(10시드), three_day_slice, four_player_equipment(host+3), two_player_combat(host+1), four_player_soak(압축 0.5분).
- **60분 soak 관문 통과 기록**: docs/technical/FOUR_PLAYER_SOAK_GATE_RECORD.md (69,178주기·치명 오류 0).
- 완성된 축: 감지 루프(냄새·바람·소리), 장비 3부작(데이터/VisualRig/넷 복제), 창·활·횃불 전투, 3구역 수직 절편(Z01→Z02→Z03), 세션 4결과(STABLE/FORCED/REMAIN/FAILED), 난이도 3종(4축 실규칙), Title→난이도→Play 진입, 입력 재바인딩, 거점(보관함·건조대·잠자리), 저장·이어하기·일시정지·사망 복구(JSON v1), 비·젖음·의상 특성, 재료 다용도·옷 수선, 사망 원인 문장·랩터 텔레그래프, 캐릭터 기록(Chronicle), 청소동물, 장비 오버레이 아트 8종(BaseBody 기본 신체화 완료).

## 2. 정본 문서 (우선순위 순)

1. `/Users/psw/Downloads/PRIMAL_NIGHT_ZOMBOID_FUN_DIRECTION.md` — **현행 제품 방향 정본** (좀보이드식 재미: 준비→욕심→실수→연쇄→귀환). §6 "만들지 말 것" 목록 준수.
2. `docs/PRIMAL_NIGHT_GITHUB_AUDIT_AND_AGENT_LOOP.md` — 실행 루프 정본 (OBSERVE→…→DECIDE, 강제 중단 관문, PR 보고 형식).
3. `docs/technical/DESIGN_DOC_CODE_ALIGNMENT.md` — 구 설계 문서와 코드의 불일치 표. 구 설계(`docs/design/GAME_SCENARIO_WORLD_TILEMAP.md`)를 읽을 땐 반드시 이 표와 함께.

핵심 판단 기준: **"공룡과 싸우는 게임이 아니라, 내가 남긴 흔적 때문에 사냥당하는 게임"** — 이 문장을 강화하지 않는 기능은 후순위.

## 3. 모델 적재적소 배치표

| 모델 | 역할 | 맡길 일 | 맡기지 말 일 |
|---|---|---|---|
| **codex gpt-5.6-sol** | 리드 엔지니어 + 에셋 담당(정책 고정) | Godot/GDScript 구현, 넷코드(호스트 권위), 시스템 설계-구현, 픽셀 에셋 생성·앵커 작업, 회귀 이분법 디버깅 | 최종 판정(코디네이터 몫), 커밋 |
| **codex gpt-5.5** | 테스트·기계적 이전·문서 | 플레이크 안정화, 테스트 보강, 문서 감사·정렬표, 반복 리팩터링, 레시피/데이터 재편 | 큰 설계 판단이 필요한 신규 시스템 |
| **opus 4.8** (claude 워커) | 냉정한 반대 검토자 | 대형 설계 착수 전 크리틱(과범위·권위 경계·회귀 위험·거짓 완료 공격), 2단계 장기 생존 모드 계획 검토, 릴리스 판단 자문 | 구현 자체(구현은 codex에) |
| **Fable 5** (코디네이터 본인) | 오케스트레이터 + 플레이 경험 평가 | 태스크 분해·디스패치·worker_done 감독, **모든 검증·커밋의 최종 권한**, GUI 실기 검증(스크린샷 판정), 퀘스트화 여부·재미 관점 검토, 사망 문구 등 서사 텍스트 감수 | — |

워커 생성 명령(코디네이터가 실행):
```bash
orca terminal create --worktree active --title <이름> \
  --command "codex -m gpt-5.6-sol -s workspace-write -a never -c sandbox_workspace_write.network_access=true" --json
# gpt-5.5도 -m 만 교체. opus 4.8 크리틱은 claude 워커 또는 코디네이터 직속 서브에이전트로.
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 90000 --json
orca orchestration task-create --spec "<상세 명세>" --json
orca orchestration dispatch --task <task_id> --to <handle> --inject --json
orca orchestration check --wait --types worker_done,escalation,decision_gate --timeout-ms 580000 --json
```

## 4. 운영 수칙 (사고 이력 기반 — 어기면 재발한다)

1. **커밋·push는 코디네이터 전권.** 태스크 명세에 "git commit/push 절대 금지, 위반 시 실패 처리"를 반드시 명시 (codex 워커가 무단 commit+push한 사례 있음: `26e3c7e`). worker_done 직후 `git log` 확인.
2. **워커 검증은 참고, 판정은 코디네이터 재검증.** 워커는 `HOME=/tmp`로 GUT를 우회 실행한다(user:// SIGSEGV). 커밋 전 코디네이터가 전체 GUT + 관련 하네스를 직접 실행.
3. **워커가 작업 중인 워크트리에서 git stash/checkout 이분법 금지.** detached HEAD·부분 stash pop 사고 이력 있음. 이분법은 트리 클린 + 워커 유휴일 때만.
4. **같은 워크트리 병렬 워커**는 파일 영역이 겹치지 않을 때만. 완료 후 합동 검증 → 파일 목록 기준 분리 커밋. 공유 파일이 있으면 기반 커밋의 함수 존재 여부를 grep으로 확인(구버전 기반 저장 사고 이력).
5. **저장 스키마는 JSON 왕복 후 int가 float이 된다** — 새 int 필드는 SaveService.load_file의 정규화 계층에 등록. 복원 테스트는 반드시 실제 파일 왕복 경유.
6. **간헐 실패는 통계로 판정** (10회 단위). 1회 통과를 증거로 삼지 않는다. 새 하네스/기능이 기존 하네스를 흔들면 stash 대조로 회귀/기존결함을 분리(단, 수칙 3 준수).
7. 검증 순서: 관련 GUT → 전체 GUT → 관련 하네스 → (UI/시각이면) GUI 실기. 초록이어도 재미·가독성은 별개 판정.

## 5. 검증 명령 모음

```bash
G=/opt/homebrew/bin/godot   # 4.7.1 (CI는 4.7-stable 리눅스)
"$G" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit   # 전체 GUT
"$G" --headless --path . -s scripts/net/four_player_soak_harness.gd                              # SOAK_MINUTES=0.05~60
"$G" --path . -s tools/visual_gallery.gd    # 장비 비주얼 갤러리 (GUI 필요, user://visual_gallery.png)
```
GUI 실기 자동화: 게임 pid를 잡아 `osascript`로 frontmost 지정 후 key code(단발)/`key down`+`key up`(이동 홀드). orca computer 클릭은 포커스만 잡히고 활성화는 Enter가 필요. 캡처는 `screencapture -x` 전체 후 크롭. 저장 파일: `~/Library/Application Support/Godot/app_userdata/PRIMAL NIGHT/saves/slot_1.save`.

## 6. 남은 작업 큐 (우선순위 순, 담당 모델)

2026-07-18 4차 세션에서 완료: ~~#1 플레이테스트 준비~~(`a8a8655` 관찰지 + `0ceb049` export 검증), ~~#3 리스폰~~(`82a1b90`), ~~#4 small_pack~~(`7c3cfdf`), ~~#6 문서 정본화~~(`e06dcd4`). GUI 실기 잔여분(#2)도 대부분 완료: 조작 설정·재바인딩, 보관함 넣기/꺼내기, 잠자리, 사망→복구 — 이 과정에서 실결함 2건 발견·수정(`2036409` 마우스 바인딩 소실, `0042633` Space 꺼내기 불가).

| # | 작업 | 담당 | 비고 |
|---|---|---|---|
| 1 | **사람 플레이테스트 실행** — docs/playtest/PLAYTEST_01_OBSERVATION_SHEET.md 사용 | **사용자**+5명 | **통과 전 신규 콘텐츠 확장 금지(§6)**. 함정: 인벤 UI Esc=장착 해제, 닫기=Tab (혼동 관찰 포인트) |
| 2 | GUI 실기 잔여: 건조대(날고기 필요)·전투(창 제작→랩터, sinew 필요) — 사냥 흐름으로 이어서 검증 | Fable 5 (실기) | 날고기·sinew는 랩터 사냥/해체로 획득. 바닥 날고기는 청소동물이 먹어치움(실관측) |
| 3 | small_pack 장착 기반 소지 용량 확장 경로 — capacity_slots/weight는 현재 modifiers 수치만 존재, 인벤토리 미연결 | gpt-5.6-sol | 큐 #4 승격 시 이월된 부채. 인벤토리 슬롯/무게 시스템에 장비 modifier 반영 설계 필요 |
| 4 | 알려진 플레이크 추적: combat 하네스 '사체 복제' 타이밍 1회 관측 이력 — 재발 시 안정화 태스크 | gpt-5.5 | tests/senses stealth 안정화(f353128) 패턴 참조 |
| 5 | **2단계 장기 생존 모드**(좀보이드 문서 §5: 3~10시간, 탈출은 선택) 착수 여부 판단 | **opus 4.8 크리틱 선행** → 계획 통과 시 gpt-5.6-sol | **1단계 플레이테스트 재미 증명 전 착수 금지** |
| 6 | push 결정 | **사용자** | 로컬 main이 origin보다 앞섬. goal_scene_replay CI 수정(e28593f)도 미push라 원격 CI는 빨간 상태일 수 있음 |

## 7. 함정 모음 (요약)

- codex 워커 플래그 없으면 worker_done 전송·ENet 테스트 실패 (`network_access=true` 필수).
- Godot 첫 설치 시 quarantine으로 무한 대기 (`xattr -dr com.apple.quarantine`).
- 하네스는 main.tscn 직접 로드 → 저장 비활성·표준 난이도 자동. 이 경로 판정을 깨는 변경 금지.
- 난이도 메뉴 초기 포커스는 '표준'(가운데) — GUI 자동화 시 방향키 카운트 주의.
- 타이틀 초기 포커스는 '싱글 시작'. 이어하기는 저장 존재 시에만 활성.
- 오케스트레이션 상태 확인: `orca orchestration task-list --brief --json`. 이전 세션 태스크는 전부 completed/blocked 처리됨.

## 8. 메모리 인덱스 (Claude 전용)

`~/.claude/projects/-Users-psw-Projects-primal-night/memory/`: `primal-night-agent-loop-progress`(사이클별 커밋 이력), `codex-orca-worker-sandbox`(워커 플래그·사고 이력), `primal-night-godot-env`(환경). 다음 세션 시작 시 갱신하며 사용할 것.

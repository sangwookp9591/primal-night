# primal-night

## 실행

```bash
# macOS — 반드시 Godot.app 으로 연다. CLI 바이너리(/opt/homebrew/bin/godot)를
# 터미널에서 직접 실행하면 창은 뜨지만 macOS 가 키보드 입력을 전달하지 않는다.
open -n /Applications/Godot.app --args --path "$(pwd)"
```

## 조작

| 키 | 동작 |
|---|---|
| WASD | 이동 (마우스 이동 없음) |
| Shift | 달리기 (소음 증가, 피로 누적) |
| Ctrl | 웅크리기 (감속, 소음 감소) |
| E | 상호작용 (줍기·모닥불 설치·치료) |
| H | 디버그 부상 (출혈 → 피 냄새) |
| F4 | 디버그 시각화 (냄새 격자·랩터 상태) |
| F6 / F7 | 바람 방향 회전 / 세기 순환 |

## 테스트

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
godot --headless --path . -s scripts/senses/sense_loop_harness.gd   # 감지 루프 10시드
```

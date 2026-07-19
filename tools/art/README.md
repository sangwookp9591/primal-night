# 캐릭터 시트 빌더 (v3)

플레이어 BaseBody·장비 오버레이 11종을 결정적으로 재생성하는 파이프라인.

```bash
cd <repo>
python3 tools/art/build_player_sheet.py assets/sprites/player/player_survivor_sheet.png
python3 tools/art/build_overlays.py /tmp/ov && cp /tmp/ov/*.png assets/sprites/player/equipment/
godot --headless --path . --import   # 텍스처 캐시 갱신 필수
```

- 셀 48x64, 열=방향 8(N,NE,E,SE,S,SW,W,NW), 행=idle2+walk4, 발 기준선=외곽선 포함 y58.
- SW/W/NW는 SE/E/NE 전체 미러. 오버레이는 base 픽셀 영역 재염색이라 프레임 자동 정합.
- 지오메트리 상수를 바꾸면 tests/player/ 방향·기준선·눈 좌표 계약도 함께 갱신할 것.

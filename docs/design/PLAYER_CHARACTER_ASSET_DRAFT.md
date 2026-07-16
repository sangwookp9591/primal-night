# PRIMAL NIGHT — 플레이어 캐릭터 에셋 초안 명세

> 상태: **초안 제안 / 미구현 / 플레이어 Scene 미연결**  
> 정책: `docs/technical/2026-07-14-asset-generation-policy.md` §2~§4  
> 대상: 현대 지질·생태 합동 구조팀 조난자 1종

## 1. 에셋 목표

- 시점: 2D 아이소메트릭 3/4, 8방향.
- 매체: 제한 팔레트 픽셀아트, 형태와 장비 실루엣 우선.
- 인물 고정: 성인 한국인, 평균 체격, 짧은 검은 머리, 녹슨 적갈색 우비, 짙은 카고 바지, 등산화, 소형 배낭, 오른손 손전등.
- 조명 고정: 좌상단의 차가운 달빛, 우하단에 짧은 접지 그림자.
- 인공색 제한: 우비의 적갈색과 장비 LED의 청록만 사용하고 네온색은 배경 키 색 외에는 사용하지 않는다.
- 범위: 대기 2프레임과 걷기 4프레임. 공격·채집·부상 애니메이션은 이번 초안에 포함하지 않는다.

## 2. 단일 시트 규격

| 항목 | 값 |
|---|---|
| 방향 열 | `N, NE, E, SE, S, SW, W, NW` 순서의 8열 |
| 동작 행 | `Idle 1, Idle 2, Walk 1, Walk 2, Walk 3, Walk 4` 순서의 6행 |
| 런타임 셀 | 48×64px |
| 런타임 시트 | 384×384px RGBA, 48셀 |
| 원점 | 각 셀 아래 중앙의 발 접점 |
| 배경 | 생성 요청은 단색 `#FF00FF`, 생성 원본의 마젠타 편차는 보존, 런타임은 투명 알파 |
| 샘플링 | Nearest, 픽셀 정수 좌표·정수 배율 |

```text
           N    NE     E    SE     S    SW     W    NW
Idle 1   [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]
Idle 2   [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]
Walk 1   [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]
Walk 2   [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]
Walk 3   [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]
Walk 4   [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]  [  ]
```

## 3. 단 한 번의 생성 요청

분류: `stylized-concept` / 스프라이트 시트 초안. 아래 문장을 한 번의 이미지 생성 요청으로 사용하며, 방향별 재생성 요청을 하지 않는다.

```text
Create one square pixel-art sprite sheet for an original survival-game player character. The sheet must be a clean 8-column by 6-row layout with generous, equal cell spacing and no drawn grid lines. Columns from left to right are the same character facing N, NE, E, SE, S, SW, W, NW. Rows from top to bottom are idle frame 1, idle frame 2, walk frame 1, walk frame 2, walk frame 3, walk frame 4. Every one of the 48 cells must show exactly the same adult Korean geology-and-ecology rescue-team survivor: average build, short black hair, muted rust-red rain jacket, charcoal cargo trousers, hiking boots, compact dark backpack, and a small flashlight held in the right hand. Preserve the exact identity, outfit, equipment side, body proportions, sprite scale, foot-anchor position, and silhouette across every cell; only facing direction and subtle animation pose may change.

Use a consistent orthographic isometric 3/4 camera suitable for a 64x32 isometric-tile game. Make each character occupy about 70 percent of a tall cell, fully visible with ample empty padding, feet aligned to the same baseline inside each cell. Crisp limited-palette pixel art, hard pixel clusters, readable silhouette, no painterly rendering, no smoothing, no antialiasing, no perspective drift. Muted natural colors: near-black shadow, charcoal green, soil brown, moon gray, muted rust red; reserve one tiny cyan accent for the equipment LED. Consistent cool moonlight from upper left and a tiny lower-right contact shadow in every cell.

Use one perfectly uniform flat chroma-key magenta #FF00FF background over the entire sheet. Do not use magenta anywhere on the character or equipment. No scenery, terrain, props beyond the worn equipment, particles, gradients, frame borders, grid lines, labels, direction letters, captions, logos, signatures, text, or watermark. No copyrighted or recognizable franchise character. This is a utilitarian production sprite-sheet draft, not an illustration.
```

## 4. 프로젝트 팔레트 초안

모든 방향과 프레임에 같은 고정 팔레트를 적용한다. 생성 원본의 색은 아래 가장 가까운 색으로 디더링 없이 양자화한다.

| 용도 | 색상 |
|---|---|
| 심야 외곽선·최심부 그림자 | `#16130E` |
| 차콜 바지·장비 | `#2B2A26` |
| 차콜 그린 중간톤 | `#2E3527` |
| 식생 반사 그림자 | `#3A4028` |
| 흙·가죽·신발 | `#5A4C38` |
| 우비 어두운 면 | `#6B352E` |
| 우비 기본색 | `#8E4438` |
| 피부 어두운 면 | `#8B6650` |
| 피부·가죽 밝은 면 | `#B08A6A` |
| 달빛 중간톤 | `#8F8C7D` |
| 달빛 하이라이트 | `#C8C4AE` |
| 장비 LED 한정 | `#6FC7C9` |

## 5. 원본·런타임 분리와 후처리

| 역할 | 경로 | 처리 |
|---|---|---|
| 생성 원본 | `assets/source/player/player_survivor_sheet_source.png` | 단 한 번 생성된 원본을 그대로 보관, 마젠타 키 배경의 생성 편차 포함 |
| 런타임 | `assets/sprites/player/player_survivor_sheet.png` | 384×384 RGBA, 키 배경 제거, 48×64 셀 그리드, 고정 팔레트 |

후처리 순서는 다음과 같다.

1. 생성 원본은 손대지 않고 `assets/source/player/`에 보존한다.
2. 마젠타 배경 투영으로 원본의 8개 열·6개 행 피사체 구간을 찾는다.
3. 모든 피사체를 같은 배율로 Nearest 축소하고 48×64px 셀 아래 중앙에 배치해 384×384에 스냅한다.
4. `#FF00FF`와 가까운 배경 픽셀을 알파 0으로 바꾸되, 피사체 가장자리의 마젠타 번짐도 거리 임계값으로 제거한다.
5. 나머지 불투명 픽셀을 위 12색 가운데 가장 가까운 색으로 디더링 없이 양자화하고, 시각 방위를 표준 8방향 열 순서로 재배치한다.
6. Godot 임포트는 프로젝트 기본값인 Nearest를 사용하고, 위치·배율은 정수로 유지한다.

이 후처리는 스프라이트의 실제 관절·장비 일관성을 새로 그리지 않는다. 원본 생성에서 발생한 방향·프레임 오류는 숨기지 않고 체크리스트에 제한으로 남기며, 이후 수작업 픽셀 정리 대상으로 취급한다.

## 6. 생성·후처리 결과

이미지 초안은 내장 이미지 생성 도구로 **한 번만 요청**해 만들었다. 생성기는 1,254×1,254px 한 장에 8열×6행, 총 48개 포즈를 반환했으며 별도의 방향별 보정 생성은 하지 않았다.

원본은 각 열의 시각 방위를 표준 런타임 순서로 완전히 정렬하지 않았기 때문에, 새 그림을 합성하지 않고 원본 열을 시각 판독해 `N, NE, E, SE, S, SW, W, NW` 순서로 재배치했다. 적용한 1기준 원본 열 순서는 `5, 1, 3, 2, 4, 7, 8, 6`이다. 이 매핑은 초안의 방위 커버리지를 정리한 것이며 실제 입력 벡터와의 회전 감각은 유보 항목대로 게임 통합 단계에서 최종 확인한다.

후처리에서는 배경 투영으로 6개 행과 8개 열의 피사체 구간을 찾고, 각 피사체를 동일 배율로 축소한 뒤 48×64px 셀의 아래 중앙에 배치했다. 이 방식으로 생성기의 미세하게 불균일한 간격을 그대로 자르면서 생기는 셀 침범을 방지했다.

| 검증값 | 결과 |
|---|---|
| 생성 요청 수 | **1회** |
| 원본 | 1,254×1,254px RGB, SHA-256 앞 16자리 `48ca4402e7b029dd` |
| 런타임 | 384×384px RGBA, SHA-256 앞 16자리 `e7b0b2089f7589b3` |
| 셀 | 48개 모두 불투명 픽셀 존재 |
| 셀 간격 | 셀 경계에 닿는 피사체 0개 |
| 불투명 팔레트 | 정확히 12색, 디더링 없음 |
| 배경 | 원본은 마젠타 키 색에 미세 편차, 런타임은 이를 제거한 투명 알파 |

### 6.1 정책 §4 최종 판정

| 점검 항목 | 판정 | 근거·한계 |
|---|---|---|
| 한 번의 생성 요청에 8방향 전체 포함 | **초안 합격** | 단일 원본 한 장·48셀, 방향별 추가 생성 없음 |
| 동일 인물·복장·장비 | **초안 합격** | 전 셀에 같은 머리·우비·카고 바지·배낭·손전등 유지 |
| 대기·걷기 프레임 포함 | **초안 합격** | 상단 2행 대기, 하단 4행 보행 포즈 |
| 카메라·스케일·광원 고정 | **초안 합격** | 동일 배율 재배치, 발 기준선 y=60, 같은 달빛 방향 |
| 투명/단색 배경·넉넉한 간격 | **합격** | 런타임 투명, 48셀 비어 있지 않음, 경계 접촉 0 |
| 글자·로고·워터마크 없음 | **합격** | 원본·런타임 전체 시각 점검 |
| 픽셀 스냅·동일 팔레트 양자화 | **합격** | 48×64 셀, 384×384, 불투명 12색 |
| 원본·런타임 분리 | **합격** | `assets/source/player/`와 `assets/sprites/player/` 분리 |
| 제3자 IP 비사용 | **합격** | 독자 캐릭터 설명과 일반 구조 장비만 사용 |
| 실제 게임 회전 확인 | **유보** | 코드·Scene 무수정 범위이므로 후속 통합에서 입력 벡터별 확인 |

생성형 원본 특성상 대기 2프레임의 차이는 작고, 손전등의 손 위치와 방향별 얼굴 비례에는 수작업 픽셀 정리 여지가 있다. 요청한 완전 단색 배경에도 미세 색 편차가 생겼지만 런타임 알파 처리에서 모두 제거했다. 따라서 이 파일은 회색 상자 교체용 **에셋 초안**이지 최종 애니메이션 승인본이 아니다.

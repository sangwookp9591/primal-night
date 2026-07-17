# PRIMAL NIGHT 생성 에셋 시트 규격 초안

- 생성 모델: GPT sol (`gpt-5.6-sol`)
- 스타일: 고해상도 페인팅 2D, 아이소메트릭 3/4 직교 시점, 저채도 자연색
- 공통 조명: 좌상단의 차가운 달빛
- 공통 후처리: 마젠타 크로마키 제거 → 목표 셀 격자 리샘플링 → 공통 42색 팔레트 양자화
- 원본: `assets/source/`
- 런타임 PNG: `assets/sprites/`
- 이미지 내 글자·로고·워터마크·타사 IP 없음

## 랩터 대기·걷기

- 원본: `assets/source/creatures/raptor_idle_walk_sheet_source.png`
- 런타임: `assets/sprites/creatures/raptor_idle_walk_sheet.png`
- 크기: 512×384px
- 셀: 64×64px
- 열 8개: `N, NE, E, SE, S, SW, W, NW`
- 행 6개: `Idle 1, Idle 2, Walk 1, Walk 2, Walk 3, Walk 4`
- 한 번의 생성 요청에서 8방향과 48프레임 전체를 생성했다.

## 랩터 사체

- 원본: `assets/source/creatures/raptor_carcass_stages_sheet_source.png`
- 런타임: `assets/sprites/creatures/raptor_carcass_stages_sheet.png`
- 크기: 512×256px
- 셀: 64×64px
- 열 8개: `N, NE, E, SE, S, SW, W, NW`
- 행 4개: `온전, 일부 해체, 대부분 해체, 해체 완료`
- 한 번의 생성 요청에서 8방향·4단계 전체를 생성했다. 중간 단계는 내장 묘사 없이
  깃털 감소, 제한적 혈흔, 뼈 실루엣만 사용하도록 전체 시트를 한 번에 보정했다.

## 월드 아이템 13종

- 원본: `assets/source/items/world_items_13_sheet_source.png`
- 런타임: `assets/sprites/items/world_items_13_sheet.png`
- 크기: 832×128px
- 셀: 64×128px
- 단일 행 13열:
  `stone, wood, fiber, bone, sinew, raw_meat, bandage, bait, smartphone,`
  `stone_knife, torch, bone_scraper, noise_lure`
- 방향 없는 아이콘형 월드 스프라이트다.

## 모닥불

- 원본: `assets/source/props/campfire_states_sheet_source.png`
- 런타임: `assets/sprites/props/campfire_states_sheet.png`
- 크기: 512×128px
- 셀: 128×128px
- 단일 행 4열: `미점화, 점화 1, 점화 2, 점화 3`
- 방향 없는 대칭 소품이다. 점화 3프레임은 돌·장작 위치를 유지하고 불꽃만 변한다.

## 원격 소음 미끼 설치물

- 원본: `assets/source/props/remote_noise_lure_source.png`
- 런타임: `assets/sprites/props/remote_noise_lure.png`
- 크기/셀: 128×128px
- 단일 방향·단일 프레임. 파손 스마트폰, 묶은 나뭇가지·뼈, 섬유 결속,
  짧은 추로 소리 장치임을 표현한다.

## 계곡 지형 타일 17종

- 원본: `assets/source/tiles/valley_terrain_tiles_sheet_source.png`
- 런타임: `assets/tiles/valley_terrain_tiles_sheet.png`
- 원본 크기: 1536×1024px
- 런타임 크기: 384×96px
- 셀: 64×32px 아이소메트릭 다이아몬드
- 그리드: 6열×3행. 마지막 셀 `(5, 2)`은 비워 둔다.
- 행 우선 인덱스:
  - `0~2`: Z01 추락 분지 — 회갈 암반·다진 흙·추락 잔해
  - `3~5`: Z02 갈대 강변 — 습지·얕은 물가·성긴 갈대
  - `6~8`: Z03 메아리 밀림 — 짙은 식생·낙엽 지면·거목 뿌리
  - `9~11`: Z04 둥지 평원 — 마른 풀·짓밟힌 흙·성긴 관목
  - `12~14`: Z05 검은 능선 — 현무암·갈라진 화산암·화산재
  - `15`: 비플레이 절벽
  - `16`: 비플레이 깊은 물
- 한 번의 생성 요청으로 전 타일을 만들고, 셀별로 64×32px에 픽셀 스냅한 뒤
  기존 에셋과 같은 42색 팔레트 계열로 양자화했다.

## 계곡 랜드마크 프롭 10종

- 원본: `assets/source/landmarks/valley_landmarks_10_sheet_source.png`
- 런타임: `assets/sprites/landmarks/valley_landmarks_10_sheet.png`
- 원본 크기: 1536×1024px
- 런타임 크기: 640×256px
- 셀: 128×128px
- 그리드: 5열×2행, 행 우선 순서:
  `S01 부서진 헬기 꼬리, S02 현무암 바람막이, S03 붉은 갈대 고리,`
  `S04 기울어진 관측 폴과 방수 상자, S05 흔들리는 수풀 띠,`
  `S06 흰 석회 동굴 입구, S07 뼈가 쌓인 거목 뿌리,`
  `S08 납작한 산란 둥지, S09 짓밟힌 마른 수로, S10 현대식 안테나 잔해`.
- 고정 구조물은 이동·회전하는 개체가 아니므로 에셋 정책 §2의 8방향 규칙 적용
  대상이 아니다. 모든 프롭은 동일한 단일 아이소메트릭 3/4 직교 시점이다.
- 현대 장비의 청록 포인트는 S01 균열 자국과 S10 장비광에만 제한했다.
- 한 번의 생성 요청으로 10종 전체를 만들고, 셀별 128×128px 픽셀 스냅과 공통
  42색 팔레트 양자화를 적용했다.

## 연결 전 확인

- 이 태스크는 씬·코드 연결을 하지 않는다.
- 연결 레인에서 랩터 시트를 실제로 8방향 회전시켜 방향 매핑과 발 기준점을 확인한다.
- 연결 레인에서 `valley_terrain_tiles_sheet.png`의 타일 인덱스와 MAP_DESIGN_DRAFT의
  Zone/비플레이 영역을 매핑하고, 랜드마크 시트는 S01~S10 스폰 프롭에 연결한다.
- Nearest 필터와 정수 좌표를 유지하고, 프레임 영역은 위 셀 크기를 그대로 사용한다.

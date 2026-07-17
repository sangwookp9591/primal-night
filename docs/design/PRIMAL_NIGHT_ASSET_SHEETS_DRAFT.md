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

## 연결 전 확인

- 이 태스크는 씬·코드 연결을 하지 않는다.
- 연결 레인에서 랩터 시트를 실제로 8방향 회전시켜 방향 매핑과 발 기준점을 확인한다.
- Nearest 필터와 정수 좌표를 유지하고, 프레임 영역은 위 셀 크기를 그대로 사용한다.

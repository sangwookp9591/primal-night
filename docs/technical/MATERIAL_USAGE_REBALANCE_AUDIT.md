# 재료 용도 충돌 제작 재편 감사

기준: `data/recipes/*.tres`에서 재료가 등장하는 서로 다른 레시피 수를 집계했다.

| 재료 | 변경 전 사용처 수 | 변경 전 레시피 | 변경 후 사용처 수 | 변경 후 레시피 |
|---|---:|---|---:|---|
| fiber | 8 | arrow, bedding, bow, drying_rack, noise_lure, stone_knife, storage_cache, torch | 9 | 기존 8종 + outfit 수선 |
| hide | 1 | bedding | 3 | bedding, hide_bait, outfit 수선 |
| sinew | 3 | bone_scraper, bow, stone_spear | 3 | bone_scraper, bow, stone_spear |
| wood | 6 | arrow, bow, drying_rack, stone_spear, storage_cache, torch | 6 | 동일 |
| stone | 3 | arrow, stone_knife, stone_spear | 2 | stone_knife, stone_spear |
| bone | 1 | bone_scraper | 3 | arrow, bone_scraper, noise_lure |
| raw_meat | 1 | bait | 2 | bait, hide_bait |
| smartphone | 1 | noise_lure | 0 | 재료 목록에서 제거 |

변경 전 전용 재료는 `hide`, `bone`, `raw_meat`, `smartphone` 4종이었다. 변경 후
실제 사용 중인 모든 재료의 사용처는 2개 이상이다. 신규 아이템은 0개이며 신규
레시피는 `craft_hide_bait`와 `repair_outfit` 두 개다.

## 절편 수량과 지식 발견

`SLICE_ENCOUNTERS`는 fiber 3개 지점, wood 2개 지점, stone 1개 지점을 제공한다.
랩터 한 마리 완전 해체는 raw_meat 4, bone 2, sinew 1, hide 1을 제공한다.
따라서 hide 1은 잠자리/강화 미끼/옷 수선 중 하나, bone 2는 뼈 긁개 또는
화살/소음 미끼, sinew 1은 조정된 활 또는 다른 도구 중 하나를 선택하게 한다.
수선의 fiber 2 + hide 1도 한 절편 안에서 획득 가능하다.

두 신규 레시피 모두 관찰 힌트와 성공 기록이 있어 기존 `CraftingKnowledge` 발견
경로에 자동 연결된다.

## 검증 결과

- 전체 GUT: 97 scripts, 560 tests, 560 pass, 0 fail, 27,838 asserts.
- 협동 하네스 PASS.
- 2인 목표 장면 하네스 PASS.
- 3일 절편 하네스 `THREE_DAY_SLICE_OK`.
- 해체 루프 하네스 10/10 seeds PASS.

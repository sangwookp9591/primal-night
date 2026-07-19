#!/usr/bin/env python3
"""legacy 착의 시트 → BaseBody(맨몸+브리프) + white_underwear(흰티+흰반바지) 변환.

소스: assets/sprites/player/player_survivor_clothed_legacy.png (48x64 x 8x6)
- 열 재매핑: N=c0, NE=c1, E=mir(c5), SE=mir(c2), S=c3, SW=c2, W=c5, NW=c6
- 붉은 바닥 그림자 제거, 배낭·재킷·바지는 위치+색 규칙으로 스킨/티/반바지 변환
- 발 기준선 59→58 (1px 위로)
사용: python3 build_legacy.py <base_out> <underwear_out>
"""
from PIL import Image
import sys

SRC = 'assets/sprites/player/player_survivor_clothed_legacy.png'
# dir(N,NE,E,SE,S,SW,W,NW) <- (src_col, mirror)
DIR_MAP = [(0, False), (1, False), (5, True), (2, True),
           (3, False), (2, False), (5, False), (6, False)]

# legacy 팔레트
SKIN_HI, SKIN_MID, SKIN_LO = (200, 196, 174), (176, 138, 106), (139, 102, 80)
RED_HI, RED_LO = (142, 68, 56), (107, 53, 46)
OLIVE_HI, OLIVE_LO = (58, 64, 40), (46, 53, 39)
TAN = (90, 76, 56)
DARK_A, DARK_B = (43, 42, 38), (22, 19, 14)
WHITE = [(238, 236, 228), (206, 203, 192), (168, 165, 154)]
BRIEF = [(96, 98, 108), (70, 72, 82)]

SKINS = {SKIN_HI, SKIN_MID, SKIN_LO}
PAINT_EXTRA = None
REDS = {RED_HI, RED_LO}
OLIVES = {OLIVE_HI, OLIVE_LO}
DARKS = {DARK_A, DARK_B}

NECK_Y = 24          # 머리/몸 경계
WAIST_Y = 41         # 티 밑단
SHORTS_END = 46      # 반바지 밑단
FEET_Y = 53          # 신발 시작

def convert_cell(cell, bake_clothes):
    """bake_clothes=True → 티/반바지 픽셀 반환(오버레이), False → 맨몸 base."""
    W, H = cell.size
    px = cell.load()
    base = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
    over = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
    bpx, opx = base.load(), over.load()

    # 행별 실루엣 경계(팔 판정·그림자 제거용)
    row_bounds = {}
    for y in range(H):
        xs = [x for x in range(W) if px[x, y][3] > 0]
        if xs: row_bounds[y] = (xs[0], xs[-1])
    # 다리 x 범위(그림자 제거): y 48..52 실루엣
    leg_min, leg_max = 48, 0
    for y in range(48, 53):
        if y in row_bounds:
            leg_min = min(leg_min, row_bounds[y][0])
            leg_max = max(leg_max, row_bounds[y][1])

    def is_edge(x, y):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < W and 0 <= ny < H) or px[nx, ny][3] == 0:
                return True
        return False

    for y in range(H):
        for x in range(W):
            p = px[x, y]
            if p[3] == 0: continue
            c = p[:3]
            ny = y - 1  # 기준선 59→58 시프트
            if ny < 0: continue
            skin_tone = SKIN_MID if c in (RED_HI, OLIVE_HI, TAN) else SKIN_LO

            if c in REDS and y >= 52:
                continue  # 붉은 바닥 그림자·신발 적색 제거(신발은 다크 픽셀로 유지)
            if c in REDS and y < 18:
                bpx[x, ny] = (*DARK_A, 255)     # 헤어 위 후드 점 → 헤어 톤
                continue

            if y <= NECK_Y:
                if c not in REDS:
                    bpx[x, ny] = (*c, 255)      # 머리(헤어·얼굴) 그대로
                    continue
                near_skin = any(
                    0 <= x + dx < W and 0 <= y + dy < H and px[x + dx, y + dy][3] > 0
                    and px[x + dx, y + dy][:3] in SKINS
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if near_skin:
                    bpx[x, ny] = (*SKIN_LO, 255)  # 얼굴 음영이 적색 팔레트 공유 — 스킨으로
                    continue
                # 후드 적색은 의류 규칙으로 흘림
            if c in SKINS:
                near_edge = y in row_bounds and \
                    (x <= row_bounds[y][0] + 2 or x >= row_bounds[y][1] - 2)
                if y > WAIST_Y or near_edge or y <= NECK_Y:
                    bpx[x, ny] = (*c, 255)      # 손·다리 등 진짜 노출 피부
                    continue
                # 재킷 하이라이트가 스킨 팔레트를 공유 — 내부는 의류로 처리
            if y >= FEET_Y and (c in DARKS or c == TAN):
                bpx[x, ny] = (*c, 255)          # 신발 유지
                continue

            if c in DARKS:
                # 외곽선은 유지, 내부 다크는 의류 음영으로
                if is_edge(x, y):
                    bpx[x, ny] = (*c, 255)
                else:
                    if y <= WAIST_Y:
                        bpx[x, ny] = (*SKIN_LO, 255)
                        opx[x, ny] = (*WHITE[2], 255)
                    elif y <= SHORTS_END:
                        bpx[x, ny] = (*BRIEF[1], 255)
                        opx[x, ny] = (*WHITE[2], 255)
                    else:
                        bpx[x, ny] = (*SKIN_LO, 255)
                continue

            if y <= WAIST_Y:
                # 몸통·팔: 재킷/스트랩 → 티(오버레이) + base는 스킨
                lum_hi = c in (RED_HI, TAN)
                # 반팔 변환: 팔뚝(외곽 2px, y>=33)은 맨살
                bare_arm = y >= 33 and y in row_bounds and \
                    (x <= row_bounds[y][0] + 2 or x >= row_bounds[y][1] - 2)
                bpx[x, ny] = (*(SKIN_MID if lum_hi else SKIN_LO), 255)
                if not bare_arm:
                    opx[x, ny] = (*(WHITE[0] if lum_hi else WHITE[1]), 255)
            elif y <= SHORTS_END:
                bpx[x, ny] = (*(BRIEF[0] if c in (OLIVE_HI, TAN, RED_HI) else BRIEF[1]), 255)
                opx[x, ny] = (*(WHITE[0] if c in (OLIVE_HI, TAN, RED_HI) else WHITE[1]), 255)
            else:
                bpx[x, ny] = (*(SKIN_MID if c in (OLIVE_HI, TAN, RED_HI) else SKIN_LO), 255)
    # ---- 실루엣 재성형: 색칠이 아니라 '반팔 티+반바지' 형태로 ----
    ELBOW_Y = 31        # 소매 절단선(이 아래 팔뚝은 맨살)
    HEM_Y = WAIST_Y - 1  # 셔츠 밑단
    SKIN_RAMP = {0: SKIN_MID, 1: SKIN_LO}

    def spans(pxm, y):
        xs = [x for x in range(48) if pxm[x, y][3] > 0]
        if not xs: return None
        return xs[0], xs[-1]

    # 1) 소매→팔뚝: y ELBOW_Y+1..WAIST_Y 에서 실루엣 가장자리 4px 밴드의
    #    오버레이(흰색)를 제거하고, base 는 1px 침식 후 스킨으로
    for y in range(ELBOW_Y, WAIST_Y + 1):
        sp = spans(bpx, y - 0)
        if sp is None: continue
        x0, x1 = sp
        if x1 - x0 < 12: continue
        for side, rng in ((0, range(x0, x0 + 4)), (1, range(x1 - 3, x1 + 1))):
            edge = x0 if side == 0 else x1
            for x in rng:
                if opx[x, y][3] > 0:
                    opx[x, y] = (0, 0, 0, 0)
                if bpx[x, y][3] > 0 and abs(x - edge) == 0:
                    bpx[x, y] = (0, 0, 0, 0)      # 팔뚝 1px 슬림
                elif bpx[x, y][3] > 0 and bpx[x, y][:3] not in SKINS \
                        and bpx[x, y][:3] not in (DARK_A, DARK_B):
                    bpx[x, y] = (*SKIN_MID, 255)
    # 2) 후드 깃 제거: y 17..22 에서 머리 폭(전행 헤어 스팬)+1 밖의 몸 픽셀 삭제
    head_sp = spans(bpx, 14) or spans(bpx, 15)
    if head_sp:
        h0, h1 = head_sp
        for y in range(17, 23):
            sp = spans(bpx, y)
            if sp is None: continue
            for x in range(48):
                if bpx[x, y][3] > 0 and (x < h0 - 1 or x > h1 + 1):
                    bpx[x, y] = (0, 0, 0, 0)
                    opx[x, y] = (0, 0, 0, 0)
    # 3) 몸통 슬림: y 24..WAIST_Y 폭 17 초과 행 양끝 1px 침식
    for y in range(24, WAIST_Y + 1):
        sp = spans(bpx, y)
        if sp is None: continue
        x0, x1 = sp
        if x1 - x0 + 1 > 17:
            for x in (x0, x1):
                bpx[x, y] = (0, 0, 0, 0)
                opx[x, y] = (0, 0, 0, 0)
    # 4) 밑단·반바지 분리: 셔츠 밑단 W2 라인, 반바지는 한 톤 어둡게
    for y in range(HEM_Y, HEM_Y + 1):
        for x in range(48):
            if opx[x, y][3] > 0:
                opx[x, y] = (*WHITE[2], 255)
    for y in range(WAIST_Y + 1, SHORTS_END + 1):
        for x in range(48):
            if opx[x, y][3] > 0 and opx[x, y][:3] == WHITE[0]:
                opx[x, y] = (*WHITE[1], 255)
    # 4.5) 팔뚝 존 스무딩: 가장자리 3px 밴드(y ELBOW..WAIST)를 깨끗한 스킨 2톤으로
    for y in range(ELBOW_Y + 1, WAIST_Y + 1):
        sp = spans(bpx, y)
        if sp is None: continue
        x0, x1 = sp
        if x1 - x0 < 12: continue
        for x in list(range(x0, x0 + 3)) + list(range(x1 - 2, x1 + 1)):
            if bpx[x, y][3] == 0: continue
            if bpx[x, y][:3] in (DARK_A, DARK_B): continue
            bpx[x, y] = (*(SKIN_MID if x <= x0 + 1 or x == x1 - 2 else SKIN_LO), 255)

    # 5) 새 실루엣 외곽선 재생성(base): 투명과 접한 몸 픽셀을 다크로
    for y in range(14, SHORTS_END + 2):
        for x in range(48):
            if bpx[x, y][3] == 0: continue
            if bpx[x, y][:3] in (DARK_A, DARK_B): continue
            exposed = any(
                not (0 <= x + dx < 48 and 0 <= y + dy < 64) or bpx[x + dx, y + dy][3] == 0
                for dx, dy in ((1, 0), (-1, 0)))
            if exposed and bpx[x, y][:3] in SKINS:
                r, g, b = bpx[x, y][:3]
                bpx[x, y] = (int(r * 0.55), int(g * 0.55), int(b * 0.55), 255)
    return base, over

TEE_TOP, SLEEVE_END, TEE_HEM = 23, 30, 40
SHORTS_TOP, SHORTS_HEM = 41, 46
W0, W1, W2 = (240, 238, 230), (210, 207, 197), (172, 169, 158)

def draw_white_set(base):
    """베이스 실루엣 위에 깨끗한 반팔 티+반바지를 새로 그린다(색칠이 아니라 의복)."""
    bpx = base.load()
    over = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
    opx = over.load()
    def span(y):
        xs = [x for x in range(48) if bpx[x, y][3] > 0]
        return (xs[0], xs[-1]) if xs else None
    PAINTABLE = SKINS | {tuple(BRIEF[0]), tuple(BRIEF[1])}
    for y in range(TEE_TOP - 2, TEE_HEM + 1):
        sp = span(y)
        if sp is None: continue
        x0, x1 = sp
        # 캡 소매 아래로는 팔(가장자리 3px) 노출
        if y > SLEEVE_END and x1 - x0 >= 12:
            x0, x1 = x0 + 3, x1 - 3
        w = max(1, x1 - x0)
        for x in range(x0, x1 + 1):
            # 스킨/브리프 픽셀만 덮는다 — 어깨 경사 추종, 헤어·외곽선 보존
            if bpx[x, y][3] == 0 or bpx[x, y][:3] not in PAINTABLE:
                continue
            t = (x - x0) / w
            c = W0 if t < 0.35 else (W1 if t < 0.8 else W2)
            if y == TEE_HEM: c = W2
            opx[x, y] = (*c, 255)
    for y in range(SHORTS_TOP, SHORTS_HEM + 1):
        sp = span(y)
        if sp is None: continue
        x0, x1 = sp
        w = max(1, x1 - x0)
        for x in range(x0, x1 + 1):
            t = (x - x0) / w
            c = W1 if t < 0.4 else (W1 if t < 0.8 else W2)
            if y == SHORTS_HEM: c = W2
            opx[x, y] = (*c, 255)
        mid = (x0 + x1) // 2
        if y >= SHORTS_TOP + 2: opx[mid, y] = (*W2, 255)
    # 목선 노치: 티 상단 중앙 2px 스킨 노출
    sp = span(TEE_TOP)
    if sp:
        mid = (sp[0] + sp[1]) // 2
        for x in (mid, mid + 1):
            if opx[x, TEE_TOP][3] > 0: opx[x, TEE_TOP] = (0, 0, 0, 0)
    return over

def build():
    src = Image.open(SRC).convert('RGBA')
    base_sheet = Image.new('RGBA', (384, 384), (0, 0, 0, 0))
    over_sheet = Image.new('RGBA', (384, 384), (0, 0, 0, 0))
    for row in range(6):
        for d, (col, mir) in enumerate(DIR_MAP):
            cell = src.crop((col * 48, row * 64, (col + 1) * 48, (row + 1) * 64))
            if mir:
                cell = cell.transpose(Image.FLIP_LEFT_RIGHT)
            base, _legacy_over = convert_cell(cell, True)
            over = draw_white_set(base)
            base_sheet.paste(base, (d * 48, row * 64))
            over_sheet.paste(over, (d * 48, row * 64))
    return base_sheet, over_sheet

if __name__ == '__main__':
    base_out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/legacy_base.png'
    over_out = sys.argv[2] if len(sys.argv) > 2 else '/tmp/legacy_underwear.png'
    b, o = build()
    b.save(base_out); o.save(over_out)
    print('saved', base_out, over_out)

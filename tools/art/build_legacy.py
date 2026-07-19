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
    return base, over

def build():
    src = Image.open(SRC).convert('RGBA')
    base_sheet = Image.new('RGBA', (384, 384), (0, 0, 0, 0))
    over_sheet = Image.new('RGBA', (384, 384), (0, 0, 0, 0))
    for row in range(6):
        for d, (col, mir) in enumerate(DIR_MAP):
            cell = src.crop((col * 48, row * 64, (col + 1) * 48, (row + 1) * 64))
            if mir:
                cell = cell.transpose(Image.FLIP_LEFT_RIGHT)
            base, over = convert_cell(cell, True)
            base_sheet.paste(base, (d * 48, row * 64))
            over_sheet.paste(over, (d * 48, row * 64))
    return base_sheet, over_sheet

if __name__ == '__main__':
    base_out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/legacy_base.png'
    over_out = sys.argv[2] if len(sys.argv) > 2 else '/tmp/legacy_underwear.png'
    b, o = build()
    b.save(base_out); o.save(over_out)
    print('saved', base_out, over_out)

#!/usr/bin/env python3
"""legacy 베이스 시트 기반 장비 오버레이 재생성(픽셀 재염색 — 프레임 자동 정합).
사용: python3 build_overlays_legacy.py <legacy_base.png> <출력디렉터리>
"""
from PIL import Image
import sys, os

BASE_PATH = sys.argv[1]
OUT_DIR = sys.argv[2]
os.makedirs(OUT_DIR, exist_ok=True)

# 변환 후 베이스 팔레트
SKIN = [(200, 196, 174), (176, 138, 106), (139, 102, 80)]
BRIEF = [(96, 98, 108), (70, 72, 82)]
SKINS = set(SKIN); BRIEFS = set(BRIEF)
NECK_Y, WAIST_Y, SHORTS_END, FEET_Y = 23, 40, 45, 52   # 1px 시프트 반영

WHITE = [(238, 236, 228), (206, 203, 192), (168, 165, 154)]
OLIVE = [(126, 128, 84), (98, 102, 64), (72, 76, 48)]
LEATHER = [(150, 106, 64), (118, 80, 48), (88, 60, 36)]
FUR = [(146, 112, 76), (112, 84, 56), (82, 60, 40)]
REED = [(122, 140, 76), (94, 112, 58), (68, 86, 44)]
BONE = [(238, 230, 212), (210, 200, 178), (170, 160, 140)]
PACK = [(96, 100, 92), (74, 78, 72), (54, 58, 54)]
WOOD = [(148, 110, 72), (116, 84, 52), (86, 60, 38)]
STONE = [(190, 188, 182), (150, 148, 142), (110, 108, 104)]
FLAME = [(255, 232, 120), (255, 176, 64), (222, 108, 36)]

base_sheet = Image.open(BASE_PATH).convert('RGBA')

def cell_of(d, r):
    return base_sheet.crop((d * 48, r * 64, (d + 1) * 48, (r + 1) * 64))

def tone(c):
    if c in SKINS: return SKIN.index(c) if c in SKIN else 1
    if c in BRIEFS: return 1 + BRIEF.index(c)
    return None

def row_bounds_of(px):
    rb = {}
    for y in range(64):
        xs = [x for x in range(48) if px[x, y][3] > 0]
        if xs: rb[y] = (xs[0], xs[-1])
    return rb

def make(d, r, torso=None, torso_arms=None, pants=None, shorts=None,
         extras=None, hem=None):
    cell = cell_of(d, r)
    px = cell.load()
    rb = row_bounds_of(px)
    out = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
    opx = out.load()
    for y in range(64):
        for x in range(48):
            p = px[x, y]
            if p[3] == 0: continue
            t = tone(p[:3])
            if t is None: continue
            near_edge = y in rb and (x <= rb[y][0] + 2 or x >= rb[y][1] - 2)
            ramp = None
            if NECK_Y < y <= WAIST_Y:
                if torso_arms is not None:
                    ramp = torso_arms
                elif torso is not None and not (y >= 32 and near_edge):
                    ramp = torso            # 반팔: 팔뚝 노출
            elif WAIST_Y < y <= SHORTS_END and shorts is not None:
                ramp = shorts
            elif WAIST_Y < y <= FEET_Y - 1 and pants is not None:
                ramp = pants
            if ramp is not None:
                opx[x, y] = (*ramp[min(t, 2)], 255)
    g = dict(rb=rb)
    if extras: extras(opx, g)
    if hem:
        yh, ramp = hem
        if yh in rb:
            for x in range(rb[yh][0] + 1, rb[yh][1]):
                if opx[x, yh][3] > 0: opx[x, yh] = (*ramp[2], 255)
    return out

def hand_anchor(d, r):
    """오른손(정면 기준) 위치: y=40 부근 실루엣 오른쪽 끝."""
    px = cell_of(d, r).load()
    rb = row_bounds_of(px)
    y = 40 if 40 in rb else (39 if 39 in rb else 41)
    if y not in rb: return (34, 41)
    if d in (2,):      # E: 몸 중앙 앞
        return (rb[y][1] - 2, y + 1)
    if d in (6,):      # W: 미러
        return (rb[y][0] + 2, y + 1)
    return (rb[y][1] - 1, y + 1)

def put(opx, x, y, c):
    if 0 <= x < 48 and 0 <= y < 64: opx[x, y] = (*c, 255)

def weapon(kind):
    def cell(d, r):
        out = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
        opx = out.load()
        hx, hy = hand_anchor(d, r)
        if kind == 'knife':
            for i in range(3): put(opx, hx, hy - 2 - i, STONE[1 if i < 2 else 0])
            put(opx, hx, hy - 1, WOOD[1]); put(opx, hx, hy, WOOD[2])
        elif kind == 'spear':
            for i in range(26):
                put(opx, hx + i // 9, hy + 5 - i, WOOD[1] if i % 5 else WOOD[2])
            tx = hx + 2
            put(opx, tx, hy - 21, STONE[1]); put(opx, tx, hy - 22, STONE[0])
            put(opx, tx + 1, hy - 21, STONE[2])
        elif kind == 'bow':
            for i in range(18):
                dxx = 2 if 4 < i < 13 else (1 if i in (3, 4, 13, 14) else 0)
                put(opx, hx + dxx, hy + 7 - i, WOOD[1])
            for i in range(0, 18, 3):
                put(opx, hx, hy + 7 - i, (216, 212, 200))
        elif kind == 'torch':
            for i in range(9):
                put(opx, hx, hy - 1 - i, WOOD[1] if i % 3 else WOOD[2])
            fy = hy - 11
            put(opx, hx, fy, FLAME[1]); put(opx, hx, fy - 1, FLAME[0])
            put(opx, hx - 1, fy, FLAME[2]); put(opx, hx + 1, fy, FLAME[1])
            put(opx, hx, fy + 1, FLAME[2])
        return out
    return cell

def backpack(d, r):
    out = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
    opx = out.load()
    px = cell_of(d, r).load()
    rb = row_bounds_of(px)
    if d in (0, 1, 7):
        for y in range(NECK_Y + 2, WAIST_Y - 2):
            if y not in rb: continue
            x0, x1 = rb[y][0] + 4, rb[y][1] - 4
            for x in range(x0, x1 + 1):
                t = (x - x0) / max(1, x1 - x0)
                put(opx, x, y, PACK[0 if t < 0.3 else (1 if t < 0.75 else 2)])
        y = NECK_Y + 6
        if y in rb:
            for x in range(rb[y][0] + 4, rb[y][1] - 3): put(opx, x, y, PACK[2])
        put(opx, 24, NECK_Y + 8, (140, 200, 200))
    elif d in (3, 4, 5):
        for y in range(NECK_Y + 1, WAIST_Y - 1):
            if y not in rb: continue
            put(opx, rb[y][0] + 4, y, PACK[1])
            put(opx, rb[y][1] - 4, y, PACK[2])
    elif d == 2:
        for y in range(NECK_Y + 2, WAIST_Y - 2):
            if y not in rb: continue
            for x in range(rb[y][0] - 2, rb[y][0] + 2): put(opx, x, y, PACK[1])
    elif d == 6:
        for y in range(NECK_Y + 2, WAIST_Y - 2):
            if y not in rb: continue
            for x in range(rb[y][1] - 1, rb[y][1] + 3): put(opx, x, y, PACK[1])
    return out

def bone_extras(opx, g):
    rb = g['rb']
    for i, y in enumerate(range(NECK_Y + 3, WAIST_Y - 1, 3)):
        if y not in rb: continue
        for x in range(rb[y][0] + 3, rb[y][1] - 2):
            if opx[x, y][3] > 0:
                opx[x, y] = (*BONE[0 if (x + i) % 4 else 1], 255)

def reed_extras(opx, g):
    rb = g['rb']
    for y in range(NECK_Y + 1, SHORTS_END + 1):
        if y not in rb: continue
        for x in range(rb[y][0], rb[y][1] + 1):
            if opx[x, y][3] > 0 and (x - rb[y][0]) % 3 == 2:
                opx[x, y] = (*REED[2], 255)

ITEMS = {
    'work_clothes_sheet.png': lambda d, r: make(d, r, torso_arms=OLIVE, pants=OLIVE,
        shorts=OLIVE, hem=(WAIST_Y, LEATHER)),
    'leather_armor_sheet.png': lambda d, r: make(d, r, torso_arms=None, torso=LEATHER,
        shorts=None, hem=(WAIST_Y, LEATHER)),
    'bone_armor_sheet.png': lambda d, r: make(d, r, torso=LEATHER, extras=bone_extras),
    'fur_cloak_sheet.png': lambda d, r: make(d, r, torso_arms=FUR, hem=(WAIST_Y, FUR)),
    'reed_raincoat_sheet.png': lambda d, r: make(d, r, torso_arms=REED, shorts=REED,
        extras=reed_extras),
    'placeholder_back_sheet.png': backpack,
    'stone_knife_sheet.png': weapon('knife'),
    'stone_spear_sheet.png': weapon('spear'),
    'bow_sheet.png': weapon('bow'),
    'torch_sheet.png': weapon('torch'),
}

MIRROR_OF = {5: 3, 6: 2, 7: 1}
# 주의: base 자체가 이미 8방향 완성본이므로 미러 없이 각 방향 셀에서 직접 생성

if __name__ == '__main__':
    for name, fn in ITEMS.items():
        sheet = Image.new('RGBA', (384, 384), (0, 0, 0, 0))
        for r in range(6):
            for d in range(8):
                sheet.paste(fn(d, r), (d * 48, r * 64))
        sheet.save(os.path.join(OUT_DIR, name))
        print('built', name)

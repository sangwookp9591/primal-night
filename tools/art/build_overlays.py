#!/usr/bin/env python3
"""장비·상태 오버레이 시트 생성 — base 지오메트리에서 파생(자동 정합).
사용: python3 build_overlays.py <출력디렉터리>
"""
from PIL import Image
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_player_sheet as bps

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else '/tmp/overlays'
os.makedirs(OUT_DIR, exist_ok=True)

SKIN_SET = {c: i for i, c in enumerate(bps.SKIN)}
BRIEF_SET = set(bps.BRIEF)

WHITE = [(240, 238, 230), (212, 208, 198), (176, 172, 162)]
OLIVE = [(126, 128, 84), (98, 102, 64), (72, 76, 48)]
LEATHER = [(150, 106, 64), (118, 80, 48), (88, 60, 36)]
FUR = [(146, 112, 76), (112, 84, 56), (82, 60, 40)]
REED = [(122, 140, 76), (94, 112, 58), (68, 86, 44)]
BONE = [(238, 230, 212), (210, 200, 178), (170, 160, 140)]
PACK = [(96, 100, 92), (74, 78, 72), (54, 58, 54)]
WOOD = [(148, 110, 72), (116, 84, 52), (86, 60, 38)]
STONE = [(190, 188, 182), (150, 148, 142), (110, 108, 104)]
FLAME = [(255, 232, 120), (255, 176, 64), (222, 108, 36)]

def geom(dir_idx, row):
    idle = row < 2
    bob = (1 if row == 1 else 0) if idle else bps.WALK_FR[row - 2][3]
    adx = 0 if idle else bps.WALK_FR[row - 2][2]
    neck_y = 17 + bob
    torso_top = neck_y + 2
    brief_top, brief_bot = 36 + bob, 40 + bob
    quarter = dir_idx in (1, 3)
    if dir_idx in bps.PROFILE:
        x0, x1 = bps.CENTER - 4, bps.CENTER + 3
    else:
        hw = 4 if quarter else 5
        x0, x1 = bps.CENTER - hw, bps.CENTER + hw
    hand_y = brief_top + 3
    if dir_idx in bps.PROFILE:
        hand = (bps.CENTER + 1 + adx // 2, hand_y + 1)
    else:
        hand = (x1 + 3, hand_y + 1)
    return dict(bob=bob, torso_top=torso_top, brief_top=brief_top,
                brief_bot=brief_bot, x0=x0, x1=x1, hand=hand, hand_y=hand_y,
                foot_y=bps.BASELINE, quarter=quarter)

def base_cell(dir_idx, row):
    return bps.build_cell(dir_idx, row)

def tone_of(c):
    if c in SKIN_SET: return min(2, SKIN_SET[c])
    if c in BRIEF_SET: return 2
    return None

def recolor_overlay(dir_idx, row, region_fn, ramp, extras_fn=None):
    """base 픽셀 중 region_fn(x,y,g)==True인 스킨/브리프 픽셀을 ramp로 재염색한 오버레이."""
    base = base_cell(dir_idx, row)
    g = geom(dir_idx, row)
    bpx = base.load()
    out = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
    opx = out.load()
    for y in range(64):
        for x in range(48):
            p = bpx[x, y]
            if p[3] == 0: continue
            t = tone_of(p[:3])
            if t is None: continue
            if region_fn(x, y, g):
                opx[x, y] = (*ramp[t], 255)
    if extras_fn: extras_fn(opx, g, dir_idx, row)
    return out

def put(opx, x, y, c):
    if 0 <= x < 48 and 0 <= y < 64:
        opx[x, y] = (*c, 255)

def run(opx, x0, x1, y, c):
    for x in range(x0, x1 + 1):
        put(opx, x, y, c)

# ---------- 의류 영역 ----------
def torso_only(x, y, g):
    return g['torso_top'] <= y < g['brief_top'] and g['x0'] <= x <= g['x1']

def torso_and_arms(x, y, g):
    return g['torso_top'] <= y <= g['hand_y'] - 2

def shorts_zone(x, y, g):
    return g['brief_top'] <= y <= g['brief_bot'] + 2 and g['x0'] <= x <= g['x1']

def pants_zone(x, y, g):
    return g['brief_top'] <= y <= g['foot_y'] - 3 and g['x0'] - 1 <= x <= g['x1'] + 1

def sheet_of(cell_fn):
    sheet = Image.new('RGBA', (384, 384), (0, 0, 0, 0))
    for row in range(6):
        cells = {d: cell_fn(d, row) for d in (0, 1, 2, 3, 4)}
        for d in (5, 6, 7):
            cells[d] = cells[bps.MIRROR_OF[d]].transpose(Image.FLIP_LEFT_RIGHT)
        for d in range(8):
            sheet.paste(cells[d], (d * 48, row * 64))
    return sheet

# ---------- 각 아이템 ----------
def white_underwear(d, r):
    def extras(opx, g, dir_idx, row):
        # 정면 목선 노치
        if dir_idx in (3, 4):
            run(opx, bps.CENTER - 1, bps.CENTER + 1, g['torso_top'], None) if False else None
            for x in range(bps.CENTER - 1, bps.CENTER + 2):
                if opx[x, g['torso_top']][3] > 0:
                    opx[x, g['torso_top']] = (0, 0, 0, 0)
        # 셔츠 밑단
        run(opx, g['x0'] + 1, g['x1'] - 1, g['brief_top'] - 1, WHITE[2])
        # 반바지 밑단
        run(opx, g['x0'] + 1, g['x1'] - 1, g['brief_bot'] + 2, WHITE[2])
    def region(x, y, g):
        return torso_only(x, y, g) or shorts_zone(x, y, g)
    return recolor_overlay(d, r, region, WHITE, extras)

def work_clothes(d, r):
    def extras(opx, g, dir_idx, row):
        run(opx, g['x0'], g['x1'], g['brief_top'] - 1, (88, 60, 36))   # 가죽 벨트
        if dir_idx in (3, 4):  # 가슴 주머니
            put(opx, g['x0'] + 3, g['torso_top'] + 4, OLIVE[2])
            put(opx, g['x0'] + 4, g['torso_top'] + 4, OLIVE[2])
    def region(x, y, g):
        return torso_and_arms(x, y, g) or pants_zone(x, y, g)
    return recolor_overlay(d, r, region, OLIVE, extras)

def leather_armor(d, r):
    def extras(opx, g, dir_idx, row):
        run(opx, g['x0'], g['x1'], g['brief_top'] + 1, LEATHER[2])  # 스커트 밑단
        # 어깨 패드
        run(opx, g['x0'] - 1, g['x0'] + 1, g['torso_top'], LEATHER[1])
        run(opx, g['x1'] - 1, g['x1'] + 1, g['torso_top'], LEATHER[2])
        # 가슴 스트랩 X
        if dir_idx in (3, 4):
            for i in range(4):
                put(opx, g['x0'] + 2 + i, g['torso_top'] + 3 + i, LEATHER[2])
                put(opx, g['x1'] - 2 - i, g['torso_top'] + 3 + i, LEATHER[2])
    def region(x, y, g):
        return (g['torso_top'] <= y <= g['brief_top'] + 1 and g['x0'] <= x <= g['x1'])
    return recolor_overlay(d, r, region, LEATHER, extras)

def bone_armor(d, r):
    def extras(opx, g, dir_idx, row):
        # 뼈 슬랫 가로줄
        for i, y in enumerate(range(g['torso_top'] + 2, g['brief_top'] - 1, 3)):
            for x in range(g['x0'] + 1, g['x1']):
                if opx[x, y][3] > 0:
                    opx[x, y] = (*BONE[0 if (x + i) % 4 else 1], 255)
        run(opx, g['x0'], g['x1'], g['brief_top'] + 1, LEATHER[2])
    def region(x, y, g):
        return (g['torso_top'] <= y <= g['brief_top'] + 1 and g['x0'] <= x <= g['x1'])
    return recolor_overlay(d, r, region, LEATHER, extras)

def fur_cloak(d, r):
    def extras(opx, g, dir_idx, row):
        # 하단 프린지(디더)
        yb = g['brief_top'] + 2
        for x in range(g['x0'] - 1, g['x1'] + 2):
            if x % 2 == 0: put(opx, x, yb, FUR[2])
        # 어깨 볼륨
        run(opx, g['x0'] - 2, g['x1'] + 2, g['torso_top'], FUR[1])
        run(opx, g['x0'] - 2, g['x0'], g['torso_top'] + 1, FUR[0])
        run(opx, g['x1'], g['x1'] + 2, g['torso_top'] + 1, FUR[2])
    def region(x, y, g):
        return (g['torso_top'] <= y <= g['brief_top'] + 1 and g['x0'] - 1 <= x <= g['x1'] + 1)
    return recolor_overlay(d, r, region, FUR, extras)

def reed_raincoat(d, r):
    def extras(opx, g, dir_idx, row):
        # 세로 갈대 스트라이프
        for y in range(g['torso_top'], g['brief_bot'] + 1):
            for x in range(g['x0'], g['x1'] + 1):
                if opx[x, y][3] > 0 and (x - g['x0']) % 3 == 2:
                    opx[x, y] = (*REED[2], 255)
        run(opx, g['x0'], g['x1'], g['brief_bot'] + 1, REED[2])
    def region(x, y, g):
        return (g['torso_top'] <= y <= g['brief_bot'] and g['x0'] - 1 <= x <= g['x1'] + 1) \
            or torso_and_arms(x, y, g)
    return recolor_overlay(d, r, region, REED, extras)

def backpack(d, r):
    def cell(dir_idx, row):
        out = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
        opx = out.load()
        g = geom(dir_idx, row)
        if dir_idx in (0, 1, 7):   # 등 팩
            px0, px1 = bps.CENTER - 5, bps.CENTER + 5
            for y in range(g['torso_top'] + 1, g['brief_top'] - 2):
                for x in range(px0, px1 + 1):
                    t = (x - px0) / max(1, px1 - px0)
                    put(opx, x, y, PACK[0 if t < 0.3 else (1 if t < 0.75 else 2)])
            run(opx, px0, px1, g['torso_top'] + 4, PACK[2])    # 플랩 라인
            put(opx, bps.CENTER, g['torso_top'] + 6, (140, 200, 200))  # 인디케이터
        elif dir_idx in (3, 4):    # 정면 스트랩
            for y in range(g['torso_top'], g['brief_top'] - 1):
                put(opx, g['x0'] + 1, y, PACK[1])
                put(opx, g['x1'] - 1, y, PACK[2])
        elif dir_idx == 2:         # 측면 슬리버(등 쪽=왼쪽)
            for y in range(g['torso_top'] + 1, g['brief_top'] - 2):
                for x in range(g['x0'] - 3, g['x0'] + 1):
                    put(opx, x, y, PACK[1 if x > g['x0'] - 2 else 2])
        return out
    return cell(d, r)

def weapon_cell(kind):
    def cell(dir_idx, row):
        out = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
        opx = out.load()
        g = geom(dir_idx, row)
        hx, hy = g['hand']
        if kind == 'knife':
            for i in range(3):
                put(opx, hx, hy - 2 - i, STONE[1 if i < 2 else 0])
            put(opx, hx, hy - 1, WOOD[1]); put(opx, hx, hy, WOOD[2])
        elif kind == 'spear':
            for i in range(24):
                x = hx + (i // 8)      # 약간 기울임
                put(opx, x, hy + 4 - i, WOOD[1] if i % 5 else WOOD[2])
            tipx = hx + 2
            put(opx, tipx, hy - 20, STONE[1]); put(opx, tipx, hy - 21, STONE[0])
            put(opx, tipx + 1, hy - 20, STONE[2]); put(opx, tipx + 1, hy - 21, STONE[1])
        elif kind == 'bow':
            for i in range(16):
                dx = 2 if 3 < i < 12 else (1 if i in (2, 3, 12, 13) else 0)
                put(opx, hx + dx, hy + 6 - i, WOOD[1])
            for i in range(16):
                put(opx, hx, hy + 6 - i, (216, 212, 200)) if i % 3 == 0 else None
        elif kind == 'torch':
            for i in range(8):
                put(opx, hx, hy - 1 - i, WOOD[1] if i % 3 else WOOD[2])
            fx, fy = hx, hy - 10
            put(opx, fx, fy, FLAME[1]); put(opx, fx, fy - 1, FLAME[0])
            put(opx, fx - 1, fy, FLAME[2]); put(opx, fx + 1, fy, FLAME[1])
            put(opx, fx, fy + 1, FLAME[2])
        return out
    return cell

ITEMS = {
    'white_underwear_sheet.png': white_underwear,
    'work_clothes_sheet.png': work_clothes,
    'leather_armor_sheet.png': leather_armor,
    'bone_armor_sheet.png': bone_armor,
    'fur_cloak_sheet.png': fur_cloak,
    'reed_raincoat_sheet.png': reed_raincoat,
    'placeholder_back_sheet.png': backpack,
    'stone_knife_sheet.png': weapon_cell('knife'),
    'stone_spear_sheet.png': weapon_cell('spear'),
    'bow_sheet.png': weapon_cell('bow'),
    'torch_sheet.png': weapon_cell('torch'),
}

if __name__ == '__main__':
    for name, fn in ITEMS.items():
        sheet_of(fn).save(os.path.join(OUT_DIR, name))
        print('built', name)

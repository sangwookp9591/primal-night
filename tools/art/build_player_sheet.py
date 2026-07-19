#!/usr/bin/env python3
"""PRIMAL NIGHT 플레이어 시트 v3 — 코디네이터 직접 제작 (draft5, 전체 프로시저럴).

소스 원화는 팔레트·비례 참조만. 머리·몸 전부 좌표 정의 픽셀 드로잉.
셀 48x64, 발 기준선 y=58, 중심 x=24. 열=N,NE,E,SE,S,SW,W,NW. 행=idle2+walk4.
SW/W/NW = SE/E/NE 전체 미러.
"""
from PIL import Image
import sys

BASELINE, CENTER = 57, 24
FRONTAL, PROFILE, BACK = {3, 4, 5}, {2, 6}, {0, 1, 7}

SKIN = [(238, 195, 152), (214, 163, 118), (180, 126, 88), (132, 84, 58)]
HAIR = [(84, 66, 52), (56, 44, 37), (36, 28, 24)]
BRIEF = [(96, 98, 108), (70, 72, 82), (52, 54, 62)]
OUTLINE = (64, 42, 32)
EYE = (28, 23, 21)

S0, S1, S2, S3 = 0, 1, 2, 3        # 스킨 톤 인덱스
H0, H1, H2 = 10, 11, 12            # 헤어 톤 키
B0, B1, B2 = 20, 21, 22            # 브리프
EYEK = 30

def C(key):
    if key < 10: return SKIN[key]
    if key < 20: return HAIR[key - 10]
    if key < 30: return BRIEF[key - 20]
    return EYE

def put(opx, x, y, key):
    if 0 <= x < 48 and 0 <= y < 64:
        opx[x, y] = (*C(key), 255)

def run(opx, x0, x1, y, key):
    for x in range(x0, x1 + 1):
        put(opx, x, y, key)

def skinrun(opx, x0, x1, y):
    """좌상단 광원 3톤 가로 런."""
    w = x1 - x0
    for x in range(x0, x1 + 1):
        t = (x - x0) / max(1, w)
        put(opx, x, y, S0 if t < 0.30 else (S1 if t < 0.74 else S2))

# ---------------- 머리 ----------------
def head_S(opx, dy=0, quarter=0):
    """정면 머리. quarter=+1이면 SE(시선 오른쪽): 얼굴 축 +1, 왼쪽 헤어 두껍게."""
    q = quarter
    # 헤어 스컬 (y6..11)
    run(opx, 20 + q, 28 + q, 6 + dy, H1)
    run(opx, 19 + q, 29 + q, 7 + dy, H1)
    put(opx, 20 + q, 7 + dy, H0); put(opx, 21 + q, 7 + dy, H0)
    run(opx, 18 + q, 30 + q, 8 + dy, H1)
    run(opx, 19 + q, 22 + q, 8 + dy, H0)
    run(opx, 18 + q, 30 + q, 9 + dy, H1)
    put(opx, 19 + q, 9 + dy, H0)
    run(opx, 18 + q, 30 + q, 10 + dy, H1)
    run(opx, 18 + q, 30 + q, 11 + dy, H1)
    put(opx, 30 + q, 9 + dy, H2); put(opx, 30 + q, 10 + dy, H2); put(opx, 30 + q, 11 + dy, H2)
    # 프린지(y12): 두 갈래 터프
    y = 12 + dy
    run(opx, 18 + q, 21 + q, y, H1); put(opx, 21 + q, y, H2)
    run(opx, 22 + q, 23 + q, y, S1)
    run(opx, 24 + q, 26 + q, y, H2)
    run(opx, 27 + q, 28 + q, y, S1)
    put(opx, 29 + q, y, H2); put(opx, 30 + q, y, H2)
    # 얼굴 (y13..19)
    y = 13 + dy
    put(opx, 18 + q, y, H1); skinrun(opx, 19 + q, 29 + q, y); put(opx, 30 + q, y, H2)
    y = 14 + dy  # 눈썹 그림자 + 귀
    put(opx, 17 + q, y, S2); put(opx, 18 + q, y, H1)
    run(opx, 19 + q, 29 + q, y, S1)
    run(opx, 21 + q, 22 + q, y, S2); run(opx, 26 + q, 27 + q, y, S2)
    put(opx, 30 + q, y, H2); put(opx, 31 + q, y, S2)
    y = 15 + dy  # 눈
    put(opx, 17 + q, y, S2)
    skinrun(opx, 18 + q, 30 + q, y)
    put(opx, 21 + q, y, EYEK); put(opx, 22 + q, y, EYEK)
    put(opx, 26 + q, y, EYEK); put(opx, 27 + q, y, EYEK)
    put(opx, 31 + q, y, S3)
    y = 16 + dy
    skinrun(opx, 18 + q, 30 + q, y)
    y = 17 + dy
    skinrun(opx, 19 + q, 29 + q, y)
    y = 18 + dy  # 입
    skinrun(opx, 19 + q, 29 + q, y)
    run(opx, 23 + q, 25 + q, y, S2)
    y = 19 + dy  # 턱
    skinrun(opx, 20 + q, 28 + q, y)

def head_N(opx, dy=0, quarter=0):
    """후면 머리(전부 헤어). quarter=+1이면 NE: 오른쪽 뺨 슬리버."""
    q = quarter
    run(opx, 20 + q, 28 + q, 6 + dy, H1)
    run(opx, 19 + q, 29 + q, 7 + dy, H1)
    run(opx, 20 + q, 23 + q, 7 + dy, H0)
    for y in range(8, 12):
        run(opx, 18 + q, 30 + q, y + dy, H1)
    put(opx, 19 + q, 8 + dy, H0); put(opx, 19 + q, 9 + dy, H0)
    for y in range(12, 18):
        run(opx, 18 + q, 30 + q, y + dy, H1)
        put(opx, 21 + q, y + dy, H2); put(opx, 25 + q, y + dy, H2); put(opx, 29 + q, y + dy, H2)
    run(opx, 19 + q, 29 + q, 18 + dy, H2)
    run(opx, 21 + q, 27 + q, 19 + dy, H2)
    if quarter:  # NE 뺨·귀 슬리버
        for y in range(13, 17):
            put(opx, 30 + q, y + dy, S1 if y > 14 else S2)
        put(opx, 29 + q, 15 + dy, S2)

def head_E(opx, dy=0):
    """우측 프로필: 뒷머리 볼륨 + 앞 1/3 얼굴, 코·귀."""
    run(opx, 20, 28, 6 + dy, H1)
    run(opx, 19, 29, 7 + dy, H1); run(opx, 20, 22, 7 + dy, H0)
    for y in range(8, 12):
        run(opx, 18, 30, y + dy, H1)
    put(opx, 19, 8 + dy, H0)
    put(opx, 18, 10 + dy, H2)
    # y12: 앞머리 끝 + 이마
    run(opx, 18, 26, 12 + dy, H1); run(opx, 27, 30, 12 + dy, S1)
    run(opx, 18, 25, 13 + dy, H1); run(opx, 26, 30, 13 + dy, S1)
    # y14: 눈썹
    run(opx, 18, 24, 14 + dy, H1); run(opx, 25, 30, 14 + dy, S1)
    run(opx, 27, 29, 14 + dy, S2)
    # y15: 눈 + 코 시작
    run(opx, 18, 23, 15 + dy, H2); run(opx, 24, 30, 15 + dy, S1)
    put(opx, 28, 15 + dy, EYEK)
    put(opx, 31, 15 + dy, S1); put(opx, 32, 15 + dy, S2)  # 콧등
    # y16: 코끝·귀
    run(opx, 19, 22, 16 + dy, H2); run(opx, 23, 30, 16 + dy, S1)
    put(opx, 24, 16 + dy, S2); put(opx, 25, 16 + dy, S2)  # 귀
    put(opx, 31, 16 + dy, S2); put(opx, 32, 16 + dy, S3)  # 코끝
    # y17: 턱선
    run(opx, 20, 21, 17 + dy, H2); run(opx, 22, 29, 17 + dy, S1)
    put(opx, 24, 17 + dy, S3)      # 귓불
    # y18: 입·턱
    run(opx, 23, 28, 18 + dy, S1); put(opx, 28, 18 + dy, S2)
    run(opx, 23, 27, 19 + dy, S2)

def draw_head(opx, dir_idx, dy):
    if dir_idx == 4: head_S(opx, dy)
    elif dir_idx == 3: head_S(opx, dy, quarter=1)
    elif dir_idx == 0: head_N(opx, dy)
    elif dir_idx == 1: head_N(opx, dy, quarter=1)
    elif dir_idx == 2: head_E(opx, dy)

# ---------------- 몸 ----------------
WALK_FR = [(4, -4, 3, 0), (1, -1, 1, 1), (-4, 4, -3, 0), (-1, 1, -1, 1)]

def body_cell(opx, dir_idx, row):
    idle = row < 2
    breath = 1 if row == 1 else 0
    if idle:
        fdx = bdx = adx = 0; bob = breath
    else:
        fdx, bdx, adx, bob = WALK_FR[row - 2]
    neck_y = 20 + bob
    torso_top = neck_y + 2
    brief_top, brief_bot = 37 + bob, 41 + bob
    leg_top, foot_y = brief_bot + 1, BASELINE
    hand_y = brief_top + 3

    # 목
    run(opx, CENTER - 2, CENTER + 1, neck_y, S1)
    put(opx, CENTER + 1, neck_y, S2)
    run(opx, CENTER - 2, CENTER + 1, neck_y + 1, S1)
    put(opx, CENTER + 1, neck_y + 1, S2)

    if dir_idx in FRONTAL or dir_idx in BACK:
        quarter = dir_idx in (1, 3)
        half_w = 5 if quarter else 6
        x0, x1 = CENTER - half_w, CENTER + half_w
        # 어깨 라운드
        skinrun(opx, x0 + 1, x1 - 1, torso_top)
        for y in range(torso_top + 1, brief_top):
            t = (y - torso_top) / max(1, brief_top - torso_top)
            shrink = 1 if t > 0.6 else 0
            skinrun(opx, x0 + shrink, x1 - shrink, y)
        if dir_idx in BACK:  # 등 음영·척추
            for y in range(torso_top + 2, brief_top - 1):
                put(opx, CENTER, y, S2)
        # 브리프
        for y in range(brief_top, brief_bot + 1):
            w = x1 - x0 - 1
            for x in range(x0 + 1, x1):
                t = (x - x0 - 1) / max(1, w - 1)
                put(opx, x, y, B0 if t < 0.3 else (B1 if t < 0.75 else B2))
        put(opx, CENTER, brief_bot, B2)
        # 다리: 정면·후면은 x 고정, 교차 들어올림 2px만
        lift_f = 2 if (not idle and fdx > 2) else 0
        lift_b = 2 if (not idle and bdx > 2) else 0
        lcx, rcx = CENTER - 3, CENTER + 3
        for y in range(leg_top, foot_y - 1 - lift_f + 1):
            skinrun(opx, lcx - 2, lcx + 1, y)
        for y in range(leg_top, foot_y - 1 - lift_b + 1):
            skinrun(opx, rcx - 1, rcx + 2, y)
        # 발(맨발 톤 다운)
        run(opx, lcx - 2, lcx + 1, foot_y - lift_f, S2)
        put(opx, lcx - 2, foot_y - lift_f, S1)
        run(opx, rcx - 1, rcx + 2, foot_y - lift_b, S2)
        put(opx, rcx - 1, foot_y - lift_b, S1)
        # 팔: 정면·후면은 스윙 대신 고정(쿼터만 1px)
        la = (-1 if adx > 0 else (1 if adx < 0 else 0)) if (not idle and quarter) else 0
        ra = -la
        arm_top = torso_top + 1 + breath
        # 어깨 연결부(팔 상단 2행은 몸통에 붙임)
        run(opx, x0 - 2, x0, arm_top, S1)
        run(opx, x1, x1 + 2, arm_top, S2)
        run(opx, x0 - 2, x0 - 1, arm_top + 1, S1)
        run(opx, x1 + 1, x1 + 2, arm_top + 1, S2)
        for i, y in enumerate(range(arm_top + 2, hand_y + 1)):
            lx = x0 - 3 + round(la / 14.0 * (i + 2))
            rx = x1 + 3 + round(ra / 14.0 * (i + 2))
            put(opx, lx - 1, y, S1); put(opx, lx, y, S2)
            put(opx, rx, y, S1); put(opx, rx + 1, y, S2)
        # 손
        put(opx, x0 - 3 + la // 3, hand_y + 1, S2)
        put(opx, x1 + 3 + ra // 3, hand_y + 1, S2)
    else:
        # 측면(E) — W는 전체 미러
        x0, x1 = CENTER - 4, CENTER + 4
        skinrun(opx, x0 + 1, x1 - 1, torso_top)
        for y in range(torso_top + 1, brief_top):
            shrink = 1 if (y - torso_top) > (brief_top - torso_top) * 0.6 else 0
            skinrun(opx, x0 + shrink, x1 - shrink, y)
        for y in range(brief_top, brief_bot + 1):
            for x in range(x0 + 1, x1):
                t = (x - x0 - 1) / max(1, x1 - x0 - 2)
                put(opx, x, y, B0 if t < 0.3 else (B1 if t < 0.75 else B2))
        f = fdx if not idle else 0
        b = bdx if not idle else 0
        # 뒷다리(어두운 램프) 먼저, 앞다리 나중
        for y in range(leg_top, foot_y - 1):
            i = y - leg_top; frac = i / max(1, foot_y - 2 - leg_top)
            bx = CENTER + round(b * frac)
            run(opx, bx - 1, bx + 2, y, S2); put(opx, bx - 1, y, S3)
        run(opx, CENTER + b - 1, CENTER + b + 3, foot_y - 1, S3)
        run(opx, CENTER + b - 1, CENTER + b + 3, foot_y, S3)
        for y in range(leg_top, foot_y - 1):
            i = y - leg_top; frac = i / max(1, foot_y - 2 - leg_top)
            fx = CENTER + round(f * frac)
            skinrun(opx, fx - 1, fx + 2, y)
        run(opx, CENTER + f - 1, CENTER + f + 3, foot_y - 1, S2)
        put(opx, CENTER + f - 1, foot_y - 1, S1)
        run(opx, CENTER + f - 1, CENTER + f + 3, foot_y, S2)
        # 팔 1개(몸 중앙 앞쪽, 스윙)
        a = adx if not idle else 0
        arm_top = torso_top + 2 + breath
        for i, y in enumerate(range(arm_top, hand_y + 1)):
            ax = CENTER + 1 + round(a / 12.0 * i)
            put(opx, ax - 1, y, S1); put(opx, ax, y, S2)
        put(opx, CENTER + 1 + a // 2, hand_y + 1, S2)

def add_outline(im):
    """외곽선: 크레비스(양옆이 몸인 1~2px 틈)는 남겨 분리를 살린다."""
    px = im.load()
    fill = []
    for y in range(64):
        for x in range(48):
            if px[x, y][3] > 0: continue
            near = any(0 <= x+dx < 48 and 0 <= y+dy < 64 and px[x+dx, y+dy][3] > 0
                       for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)))
            if not near: continue
            l1 = x - 1 >= 0 and px[x-1, y][3] > 0
            r1 = x + 1 < 48 and px[x+1, y][3] > 0
            if l1 and r1:
                fill.append((x, y))  # 1px 크레비스(팔-몸통): 외곽선으로 분리선
                continue
            l2 = any(x-d >= 0 and px[x-d, y][3] > 0 for d in (1, 2))
            r2 = any(x+d < 48 and px[x+d, y][3] > 0 for d in (1, 2))
            if l2 and r2: continue   # 2px 갭(다리 사이): 투명 유지
            fill.append((x, y))
    for x, y in fill:
        px[x, y] = (*OUTLINE, 255)
    return im

def build_cell(dir_idx, row):
    im = Image.new('RGBA', (48, 64), (0, 0, 0, 0))
    opx = im.load()
    bob = (1 if row == 1 else 0) if row < 2 else WALK_FR[row - 2][3]
    body_cell(opx, dir_idx, row)
    draw_head(opx, dir_idx, bob)
    return add_outline(im)

MIRROR_OF = {5: 3, 6: 2, 7: 1}

def build_sheet():
    sheet = Image.new('RGBA', (384, 384), (0, 0, 0, 0))
    for row in range(6):
        cells = {d: build_cell(d, row) for d in (0, 1, 2, 3, 4)}
        for d in (5, 6, 7):
            cells[d] = cells[MIRROR_OF[d]].transpose(Image.FLIP_LEFT_RIGHT)
        for d in range(8):
            sheet.paste(cells[d], (d * 48, row * 64))
    return sheet

if __name__ == '__main__':
    out_path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/base_v3.png'
    build_sheet().save(out_path)
    print('saved', out_path)

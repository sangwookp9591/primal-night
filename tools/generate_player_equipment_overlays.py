#!/usr/bin/env python3
"""Generate the deterministic 48x64 base body and equipment overlay sheets.

The legacy survivor supplies the same face, hair, palette, and animation
silhouette.  The generated base replaces its jacket/trousers with skin and
minimal briefs, while equipment is snapped to explicit torso/hand anchors.
"""

from pathlib import Path
from PIL import Image, ImageDraw


CELL_W, CELL_H = 48, 64
COLS, ROWS = 8, 6
OUT = Path("assets/sprites/player/equipment")
PLAYER_OUT = Path("assets/sprites/player/player_survivor_sheet.png")
LEGACY = Path("assets/sprites/player/player_survivor_clothed_legacy.png")

INK = "#16130e"
MOON = "#c8c4ae"
MOON_MID = "#8f8c7d"
WHITE = "#dedbc9"
WHITE_SHADE = "#9e9b8f"
CANVAS = "#4e5634"
CANVAS_DARK = "#2e3527"
LEATHER = "#5a3827"
LEATHER_DARK = "#2f2119"
WOOD = "#6b4a2e"
ROPE = "#aa8454"
STONE = "#a8aaa1"
STONE_DARK = "#565b58"
FLAME = "#df6b28"
FLAME_LIGHT = "#ffd15c"
SKIN = "#b76650"
SKIN_LIGHT = "#d49370"
SKIN_SHADE = "#754137"
BRIEFS = "#3b3730"

# Per direction (N, NE, E, SE, S, SW, W, NW), measured in the 48x64 cell.
# These are the canonical regeneration anchors. Bob/stride are added per frame.
TORSO_X = (24, 24, 23, 23, 24, 25, 25, 24)
HAND_X = (17, 31, 35, 34, 31, 17, 12, 14)
HAND_Y = (31, 32, 34, 36, 36, 36, 34, 32)
TORSO_TOP = (23, 23, 24, 24, 24, 24, 24, 23)
TORSO_HALF_WIDTH = (7, 6, 5, 6, 7, 6, 5, 6)


def poly(draw, points, fill, outline=INK):
    draw.polygon(points, fill=fill, outline=outline)


def line(draw, points, fill, width=1):
    draw.line(points, fill=fill, width=width)


def anchors(direction, frame):
    bob = 1 if frame in (1, 3, 5) else 0
    stride = (-1, 0, 1, 0)[max(0, frame - 2)] if frame >= 2 else 0
    # The survivor source occupies x=9..38, y=8..59 with feet at y=60.
    torso_x = TORSO_X[direction] + stride
    hand_x = HAND_X[direction] + stride
    hand_y = HAND_Y[direction] + bob
    return torso_x, hand_x, hand_y, bob


def draw_base_body(draw, source_cell, direction, frame):
    """Keep the original person's head and redraw an unclothed body below it."""
    # Hair and face have already been copied verbatim by make_base_body().
    cx, hx, hy, bob = anchors(direction, frame)
    top = TORSO_TOP[direction] + bob
    half = TORSO_HALF_WIDTH[direction]
    stride = (-1, 0, 1, 0)[max(0, frame - 2)] if frame >= 2 else 0

    draw.rectangle((cx - 2, top - 2, cx + 2, top + 1), fill=SKIN_SHADE)
    poly(draw, [(cx - half, top), (cx + half, top),
                (cx + half - 1, top + 15), (cx - half + 1, top + 15)], SKIN)
    line(draw, [(cx - half + 2, top + 2), (cx - half + 1, top + 12)], SKIN_LIGHT)

    # Bare arms terminate at the same hand anchors used by held equipment.
    left_hand = hx if hx < cx else cx - half - 4
    right_hand = hx if hx >= cx else cx + half + 4
    line(draw, [(cx - half + 1, top + 2), (left_hand, hy)], INK, 5)
    line(draw, [(cx - half + 1, top + 2), (left_hand, hy)], SKIN, 3)
    line(draw, [(cx + half - 1, top + 2), (right_hand, hy)], INK, 5)
    line(draw, [(cx + half - 1, top + 2), (right_hand, hy)], SKIN, 3)
    draw.rectangle((hx - 2, hy - 2, hx + 2, hy + 2), fill=SKIN_LIGHT, outline=INK)

    hip_y = top + 14
    poly(draw, [(cx - half + 1, hip_y), (cx + half - 1, hip_y),
                (cx + half - 2, hip_y + 6), (cx - half + 2, hip_y + 6)], BRIEFS)
    leg_spread = 3 + abs(stride)
    left_foot_x = cx - leg_spread - stride
    right_foot_x = cx + leg_spread + stride
    for knee_x, foot_x in ((cx - 3, left_foot_x), (cx + 3, right_foot_x)):
        line(draw, [(knee_x, hip_y + 5), (knee_x, hip_y + 14), (foot_x, 56 + bob)], INK, 6)
        line(draw, [(knee_x, hip_y + 5), (knee_x, hip_y + 14), (foot_x, 56 + bob)], SKIN, 4)
        line(draw, [(foot_x, 56 + bob), (foot_x + (-2 if foot_x < cx else 2), 58 + bob)],
             SKIN_SHADE, 3)


def draw_outfit(draw, direction, frame, kind):
    cx, _, _, bob = anchors(direction, frame)
    y = TORSO_TOP[direction] + bob
    half = TORSO_HALF_WIDTH[direction]
    if kind == "white_underwear":
        base, shade = WHITE, WHITE_SHADE
        poly(draw, [(cx - half + 1, y), (cx + half - 1, y),
                    (cx + half - 1, y + 13), (cx - half + 1, y + 13)], base)
        # Neck and arm openings keep the layer visually thin.
        draw.rectangle((cx - 2, y, cx + 2, y + 2), fill=(0, 0, 0, 0))
        line(draw, [(cx - 6, y + 9), (cx + 6, y + 9)], shade)
        poly(draw, [(cx - half, y + 12), (cx - 1, y + 12),
                    (cx - 2, y + 20), (cx - half, y + 20)], base)
        poly(draw, [(cx + 1, y + 12), (cx + half, y + 12),
                    (cx + half, y + 20), (cx + 2, y + 20)], base)
    elif kind == "work_clothes":
        poly(draw, [(cx - half - 1, y - 1), (cx + half + 1, y - 1),
                    (cx + half + 1, y + 16), (cx - half - 1, y + 16)], CANVAS)
        # Sleeves connect the torso to the actual directional hand line.
        _, hx, hy, _ = anchors(direction, frame)
        sleeve_end = (hx, hy - 3)
        shoulder = (cx + (half if hx >= cx else -half), y + 2)
        line(draw, [shoulder, sleeve_end], INK, 6)
        line(draw, [shoulder, sleeve_end], CANVAS, 4)
        poly(draw, [(cx - half, y + 15), (cx - 1, y + 15),
                    (cx - 2, y + 31), (cx - half - 1, y + 31)], CANVAS)
        poly(draw, [(cx + 1, y + 15), (cx + half, y + 15),
                    (cx + half + 1, y + 31), (cx + 2, y + 31)], CANVAS)
        line(draw, [(cx, y + 2), (cx, y + 22)], CANVAS_DARK)
        draw.rectangle((cx - 7, y + 8, cx - 3, y + 12), fill=CANVAS_DARK)
        line(draw, [(cx - 8, y + 16), (cx + 8, y + 16)], INK)
        line(draw, [(cx - 6, y + 3), (cx - 8, y + 15)], MOON_MID)
    else:
        poly(draw, [(cx - half - 1, y - 1), (cx + half + 1, y - 1),
                    (cx + half + 2, y + 7), (cx + half, y + 19),
                    (cx - half, y + 19), (cx - half - 2, y + 7)], LEATHER_DARK)
        poly(draw, [(cx - half + 1, y), (cx + half - 1, y),
                    (cx + half, y + 17), (cx - half, y + 17)], LEATHER)
        # Shoulder plates and three thick horizontal hide bands.
        draw.rectangle((cx - half - 3, y, cx - half + 1, y + 5), fill=LEATHER, outline=INK)
        draw.rectangle((cx + half - 1, y, cx + half + 3, y + 5), fill=LEATHER, outline=INK)
        for dy in (6, 12, 18):
            line(draw, [(cx - half, y + dy), (cx + half, y + dy)], ROPE)


def draw_back(draw, direction, frame):
    cx, _, _, bob = anchors(direction, frame)
    # Back is centered, with a slight visible-side shift by facing.
    cx += [0, -2, -4, -4, 0, 4, 4, 2][direction]
    y = 22 + bob
    poly(draw, [(cx - 7, y + 2), (cx - 5, y), (cx + 5, y), (cx + 7, y + 2),
                (cx + 7, y + 20), (cx - 7, y + 20)], LEATHER_DARK)
    draw.rectangle((cx - 5, y + 4, cx + 5, y + 17), fill=LEATHER, outline=INK)
    line(draw, [(cx, y + 4), (cx, y + 17)], ROPE)
    line(draw, [(cx - 6, y + 2), (cx - 8, y + 18)], ROPE)
    line(draw, [(cx + 6, y + 2), (cx + 8, y + 18)], ROPE)
    draw.rectangle((cx - 4, y + 12, cx + 4, y + 17), fill=WOOD, outline=INK)


def weapon_vector(direction):
    return [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)][direction]


def draw_weapon(draw, direction, frame, kind):
    _, hx, hy, _ = anchors(direction, frame)
    dx, dy = weapon_vector(direction)
    if kind == "stone_knife":
        tip = (hx + dx * 10, hy + dy * 10)
        line(draw, [(hx - dx * 3, hy - dy * 3), (hx + dx * 3, hy + dy * 3)], ROPE, 3)
        poly(draw, [(hx + dx * 2 - dy * 2, hy + dy * 2 + dx * 2), tip,
                    (hx + dx * 2 + dy * 2, hy + dy * 2 - dx * 2)], STONE)
    elif kind == "stone_spear":
        tail = (hx - dx * 11, hy - dy * 11)
        head = (hx + dx * 7, hy + dy * 7)
        line(draw, [tail, head], INK, 4)
        line(draw, [tail, head], WOOD, 2)
        tip = (hx + dx * 10, hy + dy * 10)
        poly(draw, [(head[0] - dy * 3, head[1] + dx * 3), tip,
                    (head[0] + dy * 3, head[1] - dx * 3)], STONE)
    elif kind == "bow":
        # Bow remains a carried overlay; aiming motion is still the rig tween.
        px, py = -dy, dx
        a = (hx + px * 5 - dx * 7, hy + py * 5 - dy * 7)
        b = (hx + px * 7, hy + py * 7)
        c = (hx + px * 5 + dx * 7, hy + py * 5 + dy * 7)
        line(draw, [a, b, c], INK, 4)
        line(draw, [a, b, c], WOOD, 2)
        line(draw, [a, c], MOON_MID)
    else:
        tail = (hx - dx * 10, hy - dy * 10)
        head = (hx + dx * 5, hy + dy * 5)
        line(draw, [tail, head], INK, 5)
        line(draw, [tail, head], WOOD, 3)
        for off in (-3, 0, 3):
            line(draw, [(head[0] - dx * off - dy * 3, head[1] - dy * off + dx * 3),
                        (head[0] - dx * off + dy * 3, head[1] - dy * off - dx * 3)], ROPE)
        flame_tip = (head[0] + dx * 4, head[1] + dy * 4 - 3)
        poly(draw, [(head[0] - 4, head[1]), flame_tip, (head[0] + 4, head[1])], FLAME)
        poly(draw, [(head[0] - 2, head[1]), (flame_tip[0], flame_tip[1] + 3),
                    (head[0] + 2, head[1])], FLAME_LIGHT, outline=FLAME)


def make_sheet(kind):
    image = Image.new("RGBA", (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    for row in range(ROWS):
        for direction in range(COLS):
            cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            draw = ImageDraw.Draw(cell)
            if kind in ("white_underwear", "work_clothes", "leather_armor"):
                draw_outfit(draw, direction, row, kind)
            elif kind == "placeholder_back":
                draw_back(draw, direction, row)
            else:
                draw_weapon(draw, direction, row, kind)
            image.alpha_composite(cell, (direction * CELL_W, row * CELL_H))
    image.save(OUT / f"{kind}_sheet.png", optimize=True)


def make_base_body():
    source = Image.open(LEGACY).convert("RGBA")
    image = Image.new("RGBA", source.size, (0, 0, 0, 0))
    for row in range(ROWS):
        for direction in range(COLS):
            source_cell = source.crop((direction * CELL_W, row * CELL_H,
                                       (direction + 1) * CELL_W, (row + 1) * CELL_H))
            cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            # Preserve the exact original hair/face pixels and transparency.
            cell.alpha_composite(source_cell.crop((0, 0, CELL_W, 24)), (0, 0))
            draw_base_body(ImageDraw.Draw(cell), source_cell, direction, row)
            image.alpha_composite(cell, (direction * CELL_W, row * CELL_H))
    image.save(PLAYER_OUT, optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if not LEGACY.exists():
        raise FileNotFoundError(f"Preserved clothed source is required: {LEGACY}")
    make_base_body()
    for kind in (
        "white_underwear", "work_clothes", "leather_armor", "placeholder_back",
        "stone_knife", "stone_spear", "bow", "torch",
    ):
        make_sheet(kind)


if __name__ == "__main__":
    main()

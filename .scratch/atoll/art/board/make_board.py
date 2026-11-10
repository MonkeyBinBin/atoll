#!/usr/bin/env python3
"""Generate the ticket-02 style exploration board.

Sprites are hand-authored 16x16 pixel maps (one char per pixel) and are
palette-locked: every pixel resolves to a palette key of its direction.

Usage:  python3 make_board.py        (writes next to this script)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
SIZE = 16
PREVIEW = 8
APPEARANCES = ("claude", "codex", "generic")
APPEARANCE_LABEL = {"claude": "Claude Code", "codex": "Codex", "generic": "Generic"}

# Map legend (shared by all directions; each direction defines the colors):
#   .  transparent
#   o  outline (dark-tinted color, never black)
#   d  body shadow     b  body mid     l  body light     r  rim light
#   x  dither of b/d (checkerboard)
#   v  visor / face plate              e  eye glow
#   k  joint / bolt accent
#   S  individual color (light)        s  individual color (dark)
# Individual colors only appear on S/s pixels (scarf + antenna tip).


def rows(block):
    lines = [ln for ln in block.strip("\n").split("\n")]
    lines = [ln.strip() for ln in lines]
    assert len(lines) == SIZE, f"expected 16 rows, got {len(lines)}"
    for ln in lines:
        assert len(ln) == SIZE, f"row width {len(ln)} != 16: {ln!r}"
    return lines


def compose(head, body):
    """Head block (rows 0..n) on top of body block (remaining rows)."""
    h = [ln.strip() for ln in head.strip("\n").split("\n")]
    b = [ln.strip() for ln in body.strip("\n").split("\n")]
    return rows("\n".join(h + b))


# --------------------------------------------------------------------------
# Direction A: Neon Rim (cool, slim, angular, dark visor faces, cyan rim)
# --------------------------------------------------------------------------
A_BODY = """
....sSSSSSSs....
....oSrbbbdo....
...korbllbdok...
....orbbbbdo....
.....oddddo.....
.....ko..ok.....
.....kk..kk.....
"""

A = {
    "slug": "a-neon-rim",
    "name": "A / Neon Rim",
    "mood": "Cool night-city signage. Slim angular bodies, dark visor faces with "
            "glowing eyes, cyan rim light on the top-left edge. Indigo outlines.",
    "palette": {
        "o": ("#2E3584", "outline (deep indigo)"),
        "d": ("#4058B0", "body shadow"),
        "b": ("#6F90E8", "body mid"),
        "l": ("#AFC8FF", "body light"),
        "r": ("#8CF8FF", "rim light (cyan)"),
        "v": ("#161B4A", "visor"),
        "e": ("#ECFFFF", "eye glow"),
        "k": ("#9AA6D6", "joints / bolts"),
    },
    "states": {"error": "#FF3B5C", "waiting": "#FFD23F", "unknown": "#7E849E"},
    "individual": [("#FF6AD5", "#A3338C"), ("#7DFF8A", "#2F9C4C"), ("#B98BFF", "#5E40B5")],
    "sprites": {
        "claude": compose("""
................
................
.....oooooo.....
...oorrrrbboo...
..orrbbbbbbbdo..
.korvvvvvvvvdok.
.korvevvvvevdok.
..orvvvvvvvvdo..
...oddddddddo...
""", A_BODY),
        "codex": compose("""
................
...oooooooooo...
...orrrrrrrdo...
..korvvvvvvdok..
..koreevveedok..
...orvvvvvvdo...
...orbbbbbbdo...
...oddddddddo...
...oooooooooo...
""", A_BODY),
        "generic": compose("""
.......SS.......
.......sS.......
........k.......
......oooo......
.....orrbdo.....
....orveevdo....
....orvvvvdo....
.....orbdo......
......oddo......
""", A_BODY),
    },
}

# --------------------------------------------------------------------------
# Direction B: Toy Chunky (warm, big-head squat toys, flat 2-tone, plum lines)
# --------------------------------------------------------------------------
B_BODY = """
....oSSSSSSo....
...kobsbbbdok...
...kobbbbbdok...
....oddddddo....
....oko..oko....
....ooo..ooo....
"""

B = {
    "slug": "b-toy-chunky",
    "name": "B / Toy Chunky",
    "mood": "Warm vinyl-toy look. Oversized heads on stubby bodies, flat two-tone "
            "shading, painted-on eyes, plum outlines that read as a soft edge on black.",
    "palette": {
        "o": ("#7A3F6E", "outline (plum)"),
        "d": ("#E39A63", "body shadow (tan)"),
        "b": ("#FFE2B5", "body mid (cream)"),
        "l": ("#FFF8EC", "body light"),
        "v": ("#4A2A58", "visor / painted eyes base"),
        "e": ("#3A1F45", "painted eye"),
        "k": ("#7FD6C6", "joints / bolts (teal)"),
        "r": ("#FFFFFF", "specular dot"),
    },
    "states": {"error": "#FF4A3D", "waiting": "#FFC93C", "unknown": "#9A8F8A"},
    "individual": [("#5EC8FF", "#2A6FB0"), ("#6EE07A", "#2F8A4A"), ("#D78BFF", "#7E43B0")],
    "sprites": {
        "claude": compose("""
................
.....oooooo.....
...oobbbbbboo...
..oblrbbbbbbdo..
.obllbbbbbbbbdo.
kobbeebbbbeebdok
kobbeebbbbeebdok
.obbbbbbbbbbddo.
..oddddddddddo..
...oooooooooo...
""", B_BODY),
        "codex": compose("""
................
..oooooooooooo..
..obllbbbbbbdo..
..obvvvvvvvvdo..
..obvrrvvrrvdo..
..obvvvvvvvvdo..
..obbbbbbbbbdo..
..oddddddddddo..
..oooooooooooo..
.....oo..oo.....
""", B_BODY),
        "generic": compose("""
.......SS.......
.......sS.......
........k.......
.....oooooo.....
....obllbbbo....
...oblbbbbbdo...
...obbebbebdo...
...obbebbebdo...
....oddddddo....
.....oooooo.....
""", B_BODY),
    },
}

# --------------------------------------------------------------------------
# Direction C: Pastel Soft (no hard outline, round blobby, dithered shading)
# --------------------------------------------------------------------------
C_BODY = """
....sSSSSSSs....
...lSbbbbbbxd...
...lbbbbbbxxd...
....bbbbbxxd....
.....bx..xd.....
.....dd..dd.....
"""

C = {
    "slug": "c-pastel-soft",
    "name": "C / Pastel Soft",
    "mood": "Soft pastel plush. Round blobby silhouettes with no line art: the edge "
            "is a dithered lilac shadow plus a white rim. Mint glowing eyes on a soft visor.",
    "palette": {
        "r": ("#FFFFFF", "rim light"),
        "l": ("#F1ECFF", "body light"),
        "b": ("#CFC4FF", "body mid (lilac)"),
        "d": ("#9483DA", "body shadow / edge"),
        "o": ("#6E5DB8", "deep edge (selective)"),
        "v": ("#4A3E8E", "visor"),
        "e": ("#7CFFD9", "eye glow (mint)"),
        "k": ("#B8F0FF", "bolts"),
    },
    "states": {"error": "#FF5A6E", "waiting": "#FFE066", "unknown": "#A7A3B8"},
    "individual": [("#6FE6FF", "#2E8FB5"), ("#FF8FD8", "#B04E93"), ("#A6F28C", "#4E9B4E")],
    "sprites": {
        "claude": compose("""
................
................
.....rrlllb.....
...rrllllbbbb...
..rllbbbbbbbbx..
.klbvvvvvvvvbxk.
.klbvevvvvevbxk.
..lbvvvvvvvvxd..
...bbbbbbbbxd...
....dxdxdxdd....
""", C_BODY),
        "codex": compose("""
................
..rrrrrrrllllb..
..rlllllllllbx..
..lbvvvvvvvvbx..
..lbveevveevbx..
..lbvvvvvvvvbx..
..lbbbbbbbbbxd..
..lxbxbxbxbxdd..
...dddddddddd...
......bd..bd....
""", C_BODY),
        "generic": compose("""
.......SS.......
.......sS.......
........k.......
......rrll......
.....rlllbb.....
....rlvvvvbx....
....lbveevbx....
....lbvvvvxd....
.....bbbbxd.....
......dxdd......
""", C_BODY),
    },
}

DIRECTIONS = [A, B, C]


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------
def hex_rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def color_table(direction, indiv):
    t = {k: v[0] for k, v in direction["palette"].items()}
    t["S"], t["s"] = indiv
    return t


def render(direction, appearance, indiv_index):
    indiv = direction["individual"][indiv_index]
    table = color_table(direction, indiv)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()
    for y, line in enumerate(direction["sprites"][appearance]):
        for x, ch in enumerate(line):
            if ch == ".":
                continue
            if ch == "x":
                ch = "b" if (x + y) % 2 == 0 else "d"
            assert ch in table, f"{direction['slug']}/{appearance}: unknown key {ch!r}"
            px[x, y] = hex_rgba(table[ch])
    return img


def scale(img, n):
    return img.resize((img.width * n, img.height * n), Image.NEAREST)


def font(size):
    for path in ("/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Menlo.ttc"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def all_colors(direction):
    """(hex, role) list for the whole palette, in display order."""
    out = [(h, role) for h, role in direction["palette"].values()]
    for name, h in direction["states"].items():
        out.append((h, f"state: {name}"))
    for i, (light, dark) in enumerate(direction["individual"], 1):
        out.append((light, f"individual {i} light"))
        out.append((dark, f"individual {i} dark"))
    return out


def swatch_image(direction, cell=48, cols=8):
    colors = all_colors(direction)
    n_rows = (len(colors) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell, n_rows * cell), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    for i, (h, _) in enumerate(colors):
        x, y = (i % cols) * cell, (i // cols) * cell
        d.rectangle([x + 4, y + 4, x + cell - 5, y + cell - 5], fill=hex_rgba(h))
    return img


def capsule_strip(sprites, gap, pad_x, pad_y):
    """Black capsule with sprites side by side, on a grey 'menu bar' backdrop."""
    w = pad_x * 2 + len(sprites) * SIZE + (len(sprites) - 1) * gap
    h = SIZE + pad_y * 2
    margin = 4
    img = Image.new("RGBA", (w + margin * 2, h + margin * 2), hex_rgba("#3A3A3C"))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([margin, margin, margin + w - 1, margin + h - 1], radius=h // 2,
                        fill=(0, 0, 0, 255))
    x = margin + pad_x
    for s in sprites:
        img.alpha_composite(s, (x, margin + pad_y))
        x += SIZE + gap
    return img


def check_palette_lock(direction, img, indiv_index):
    allowed = {hex_rgba(h) for h in color_table(direction, direction["individual"][indiv_index]).values()}
    for p in img.get_flattened_data():
        if p[3] == 0:
            continue
        assert p in allowed, f"{direction['slug']}: off-palette pixel {p}"


def build():
    board_rows = []
    for direction in DIRECTIONS:
        ddir = OUT / direction["slug"]
        ddir.mkdir(exist_ok=True)
        sprites = {}
        for i, app in enumerate(APPEARANCES):
            img = render(direction, app, i)
            check_palette_lock(direction, img, i)
            sprites[app] = img
            img.save(ddir / f"{app}-idle.png")
            bg = Image.new("RGBA", img.size, (0, 0, 0, 255))
            bg.alpha_composite(img)
            scale(bg, PREVIEW).save(ddir / f"{app}-idle@8x.png")

        swatch_image(direction).save(ddir / "palette.png")
        lines = [f"{h}  {role}" for h, role in all_colors(direction)]
        (ddir / "palette.txt").write_text("\n".join(lines) + "\n")

        strip = capsule_strip([sprites[a] for a in APPEARANCES], gap=6, pad_x=12, pad_y=4)
        strip.save(ddir / "island@1x.png")
        scale(strip, 2).save(ddir / "island@2x.png")
        board_rows.append((direction, sprites, strip))

    make_board(board_rows)


def make_board(board_rows):
    cell = SIZE * PREVIEW            # 128
    gap = 24
    left = 32
    sw = 24
    sw_cols = 6
    sw_w = 200
    width = left * 2 + sw_cols * sw_w
    f_title, f_head, f_body, f_small = font(26), font(20), font(14), font(12)
    measure = ImageDraw.Draw(Image.new("RGBA", (1, 1)))

    def wrap(text, f, max_w):
        out, line = [], ""
        for word in text.split():
            trial = f"{line} {word}".strip()
            if measure.textlength(trial, font=f) <= max_w:
                line = trial
            else:
                out.append(line)
                line = word
        return out + [line]

    def row_height(direction):
        n_mood = len(wrap(direction["mood"], f_small, width - left * 2))
        n_sw = (len(all_colors(direction)) + sw_cols - 1) // sw_cols
        return 44 + n_mood * 16 + 12 + cell + 34 + n_sw * (sw + 14) + 24

    height = 76 + sum(row_height(r[0]) for r in board_rows)
    board = Image.new("RGBA", (width, height), hex_rgba("#121214"))
    d = ImageDraw.Draw(board)
    d.text((left, 24), "herdr agent island / style exploration: native 16x16, previews 8x",
           font=f_title, fill=hex_rgba("#F2F2F7"))

    y = 76
    for direction, sprites, strip in board_rows:
        d.line([(left, y), (width - left, y)], fill=hex_rgba("#2C2C2E"), width=1)
        d.text((left, y + 12), direction["name"], font=f_head, fill=hex_rgba("#F2F2F7"))
        ty = y + 44
        for line in wrap(direction["mood"], f_small, width - left * 2):
            d.text((left, ty), line, font=f_small, fill=hex_rgba("#AEAEB2"))
            ty += 16
        sy = ty + 12
        for i, app in enumerate(APPEARANCES):
            x = left + i * (cell + gap)
            d.rectangle([x, sy, x + cell - 1, sy + cell - 1], fill=(0, 0, 0, 255))
            board.alpha_composite(scale(sprites[app], PREVIEW), (x, sy))
            d.text((x, sy + cell + 8), APPEARANCE_LABEL[app], font=f_body,
                   fill=hex_rgba("#D1D1D6"))
        # island previews: actual 1x and 2x
        ix = left + 3 * cell + 2 * gap + 56
        d.text((ix, sy), "island 1x (1px = 1pt)", font=f_small, fill=hex_rgba("#AEAEB2"))
        board.alpha_composite(strip, (ix, sy + 18))
        d.text((ix, sy + 18 + strip.height + 12), "island 2x", font=f_small,
               fill=hex_rgba("#AEAEB2"))
        board.alpha_composite(scale(strip, 2), (ix, sy + 18 + strip.height + 30))
        # palette swatches with hex + role
        py = sy + cell + 34
        for j, (h, role) in enumerate(all_colors(direction)):
            cx = left + (j % sw_cols) * sw_w
            cy = py + (j // sw_cols) * (sw + 14)
            d.rectangle([cx, cy, cx + sw - 1, cy + sw - 1], fill=hex_rgba(h),
                        outline=hex_rgba("#3A3A3C"))
            d.text((cx + sw + 6, cy - 2), h.upper(), font=f_small, fill=hex_rgba("#D1D1D6"))
            d.text((cx + sw + 6, cy + 13), role, font=font(10), fill=hex_rgba("#8E8E93"))
        y += row_height(direction)
    board.save(OUT / "board.png")


if __name__ == "__main__":
    build()
    print("ok:", OUT)

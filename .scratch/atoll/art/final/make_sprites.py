#!/usr/bin/env python3
"""Final sprites (tickets 15–17), direction B / Toy Chunky.

Single source of truth for the shipped character art. Writes, in the app's asset format:
  Sources/Atoll/Resources/Sprites/{claude,codex,generic,icons,effects}.{png,json}
and QA previews + palette into this folder (art/final/).

Accessory pixels are painted with key colors (#FF00FF light, #B000B0 dark); the app swaps
them for the agent's individual color pair at load time.

Effects come from pixelfx/effects.frames.json (regenerate with pixelfx/fetch.sh + pixelfx/render.mjs).

Run: python3 .scratch/atoll/art/final/make_sprites.py
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT / "Sources" / "Atoll" / "Resources" / "Sprites"
S = 16

# ---------------------------------------------------------------- palette (ticket 15)
PALETTE = {
    # character
    "o": "#7A3F6E",  # outline (plum)
    "d": "#E39A63",  # body shadow (tan)
    "b": "#FFE2B5",  # body mid (cream)
    "l": "#FFF8EC",  # body light
    "v": "#4A2A58",  # visor
    "e": "#3A1F45",  # painted eye
    "k": "#7FD6C6",  # joints / hands (teal)
    "r": "#FFFFFF",  # specular / sparkle
    # states
    "R": "#FF4A3D",  # error red
    "Y": "#FFC93C",  # waiting yellow
    "g": "#9A8F8A",  # unknown grey
    "G": "#5E5652",  # unknown grey dark
    # exited (dim)
    "m": "#6A4A62",  # dim body
    "n": "#43283F",  # dim outline
    "z": "#A9B4FF",  # sleep z
}
KEY_LIGHT = "#FF00FF"
KEY_DARK = "#B000B0"

INDIVIDUALS = [  # light, dark — all clear of error red (~5°) and waiting yellow (~45°)
    ("#5EC8FF", "#2A6FB0"),  # sky
    ("#6EE07A", "#2F8A4A"),  # green
    ("#D78BFF", "#7E43B0"),  # violet
    ("#7A8CFF", "#3A47B0"),  # indigo
    ("#F06BE6", "#9A2E92"),  # magenta
    ("#5EF0E8", "#1F8F8A"),  # cyan
    ("#F4F4FF", "#9A9AB8"),  # silver
    ("#A8F060", "#5A9A2A"),  # lime
]
STATE_COLORS = {
    "error": PALETTE["R"], "waiting": PALETTE["Y"], "unknown": PALETTE["g"],
    "working": "#7FD6C6", "done": "#B9F2A6", "idle": "#C9B8D8", "exited": "#7A6A80",
}

# ---------------------------------------------------------------- base sprites (from board B)
BODY = [
    "....oSSSSSSo....",
    "...kobsbbbdok...",
    "...kobbbbbdok...",
    "....oddddddo....",
    "....oko..oko....",
    "....ooo..ooo....",
]
HEADS = {
    "claude": [
        "................",
        ".....oooooo.....",
        "...oobbbbbboo...",
        "..oblrbbbbbbdo..",
        ".obllbbbbbbbbdo.",
        "kobbeebbbbeebdok",
        "kobbeebbbbeebdok",
        ".obbbbbbbbbbddo.",
        "..oddddddddddo..",
        "...oooooooooo...",
    ],
    "codex": [
        "................",
        "..oooooooooooo..",
        "..obllbbbbbbdo..",
        "..obvvvvvvvvdo..",
        "..obvrrvvrrvdo..",
        "..obvvvvvvvvdo..",
        "..obbbbbbbbbdo..",
        "..oddddddddddo..",
        "..oooooooooooo..",
        ".....oo..oo.....",
    ],
    "generic": [
        ".......SS.......",
        ".......sS.......",
        "........k.......",
        ".....oooooo.....",
        "....obllbbbo....",
        "...oblbbbbbdo...",
        "...obbebbebdo...",
        "...obbebbebdo...",
        "....oddddddo....",
        ".....oooooo.....",
    ],
}
# Eye pixels per appearance and what they become when closed / turned red.
EYES = {"claude": "e", "codex": "r", "generic": "e"}
CLOSED = {"claude": "b", "codex": "v", "generic": "b"}


def base(appearance):
    rows = HEADS[appearance] + BODY
    assert len(rows) == S and all(len(r) == S for r in rows), appearance
    return [list(r) for r in rows]


def copy(g):
    return [row[:] for row in g]


def shift(g, dx=0, dy=0, rows=None):
    """Shift pixels (optionally only rows in `rows`) by dx/dy; vacated pixels become transparent."""
    out = copy(g) if rows is not None else [["."] * S for _ in range(S)]
    src = range(S) if rows is None else rows
    if rows is not None:
        for y in src:
            out[y] = ["."] * S
    for y in src:
        for x in range(S):
            ch = g[y][x]
            nx, ny = x + dx, y + dy
            if ch != "." and 0 <= nx < S and 0 <= ny < S:
                out[ny][nx] = ch
    return out


def put(g, pts, ch):
    for x, y in pts:
        if 0 <= x < S and 0 <= y < S:
            g[y][x] = ch
    return g


def replace(g, mapping, region=None):
    out = copy(g)
    for y in range(S):
        for x in range(S):
            if region and not region(x, y):
                continue
            out[y][x] = mapping.get(out[y][x], out[y][x])
    return out


def eyes(g, appearance, to):
    """Replace eye pixels in the head (rows 0-9)."""
    e = EYES[appearance]
    return replace(g, {e: to}, region=lambda x, y: y < 10)


def half_blink(g, appearance):
    """Close the top row of each eye."""
    e = EYES[appearance]
    out = copy(g)
    for y in range(10):
        for x in range(S):
            if out[y][x] == e and y + 1 < S and g[y + 1][x] == e:
                out[y][x] = CLOSED[appearance]
    return out


def closed(g, appearance):
    return eyes(g, appearance, CLOSED[appearance] if appearance != "codex" else "v")


# Arms: hands are the teal 'k' pixels at x=3 / x=12 on rows 11-12.
def arm_up(g, side):
    out = copy(g)
    x_body, x_out = (3, 2) if side == "left" else (12, 13)
    for y in (11, 12):
        out[y][x_body] = "."
    put(out, [(x_body, 10)], "o")
    put(out, [(x_out, 9)], "o")
    put(out, [(x_out, 8)], "k")
    return out


def arm_high(g, side="right"):
    """Hand raised above the head at the top-right (needs-you): reads even beside wide heads."""
    out = copy(g)
    for y in (11, 12):
        out[y][12] = "."
    put(out, [(12, 10), (13, 10)], "o")
    for y in range(3, 10):
        if out[y][14] == ".":
            out[y][14] = "o"
    if out[3][15] == ".":
        out[3][15] = "o"
    put(out, [(14, 1), (15, 1), (14, 2), (15, 2)], "k")
    put(out, [(14, 0), (15, 0)], "o")
    return out


def arm_typing(g, side):
    out = copy(g)
    x = 3 if side == "left" else 12
    out[12][x] = "."
    put(out, [(x + (1 if side == "left" else -1), 12)], "k")
    return out


def checker(g, keep_even=True):
    out = copy(g)
    for y in range(S):
        for x in range(S):
            if ((x + y) % 2 == 0) != keep_even:
                out[y][x] = "."
    return out


def sparse(g, keep):
    """Keep only pixels where (x*7 + y*3) % 4 < keep (deterministic dissolve)."""
    out = copy(g)
    for y in range(S):
        for x in range(S):
            if (x * 7 + y * 3) % 4 >= keep:
                out[y][x] = "."
    return out


def frames_for(appearance):
    g = base(appearance)
    blink = half_blink(g, appearance)
    up = shift(g, 0, -1, rows=range(0, 14))   # body bobs, feet stay
    f = {}

    # starting (4, once → working): materialise; frame 0 already shows the silhouette.
    f["starting"] = [
        put(sparse(g, 2), [(1, 2), (14, 4)], "r"),
        put(sparse(g, 3), [(0, 6), (15, 1)], "r"),
        put(copy(g), [(1, 1), (14, 3)], "r"),
        g,
    ]

    # working (6, loop): 0/1 are the calm pair (tiny bob); 2-5 type with both hands.
    f["working"] = [
        g,
        up,
        arm_typing(g, "left"),
        shift(arm_typing(g, "right"), 0, -1, rows=range(0, 14)),
        arm_typing(g, "right"),
        shift(arm_typing(g, "left"), 0, -1, rows=range(0, 14)),
    ]

    # needs_you (4, loop): hand raised high and waving; kind bubble is an overlay (icons).
    raised = arm_high(g, "right")
    wave = copy(raised)
    put(wave, [(14, 0), (15, 0), (15, 1), (15, 2)], ".")
    put(wave, [(13, 0), (14, 0), (13, 1), (14, 1)], "k")
    put(wave, [(14, 2)], "o")
    f["needs_you"] = [raised, half_blink(raised, appearance), wave, raised]

    # done (6, once → idle): cheer with both arms, little hop, sparkles.
    cheer = arm_up(arm_up(g, "left"), "right")
    hop = shift(cheer, 0, -1)
    f["done"] = [
        put(copy(cheer), [(0, 2), (15, 3)], "r"),
        hop,
        put(shift(cheer, 0, -2), [(0, 1), (15, 0), (1, 5), (14, 6)], "r"),
        put(copy(hop), [(0, 4), (15, 5)], "r"),
        cheer,
        g,
    ]

    # idle (4, loop): slow breathing; 0/1 calm pair.
    f["idle"] = [g, up, g, blink]

    # error (4, once, hold last): red eyes + "!", shake, slump.
    red = eyes(g, appearance, "R")
    bang = [(15, 0), (15, 1), (15, 2), (15, 4)]
    f["error"] = [
        put(copy(red), bang, "R"),
        put(shift(red, -1, 0), bang, "R"),
        put(shift(red, 1, 0), bang, "R"),
        put(shift(eyes(blink, appearance, "R"), 0, 1, rows=range(0, 14)), bang, "R"),
    ]

    # interrupted (3, once): "stop" — both hands out, then settle.
    stop = arm_up(arm_up(g, "left"), "right")
    f["interrupted"] = [put(copy(stop), [(0, 3), (15, 3)], "k"), stop, g]

    # exited (1): dim, eyes shut, z.
    sleep = replace(closed(g, appearance), {"b": "m", "l": "m", "d": "n", "o": "n", "k": "n", "v": "n", "r": "n",
                                             "S": "n", "s": "n", "e": "n"})
    f["exited"] = [put(sleep, [(13, 1), (14, 1), (14, 2), (13, 3), (14, 3)], "z")]

    # unknown (1): greyscale + "?".
    grey = replace(g, {"b": "g", "l": "g", "d": "G", "o": "G", "k": "g", "v": "G", "e": "G", "r": "g",
                       "S": "g", "s": "G"})
    f["unknown"] = [put(grey, [(13, 0), (14, 0), (15, 1), (14, 2), (14, 4)], "r")]
    return f


TAGS = [  # name, fps, loop, next, hold
    ("starting", 8, False, "working", None),
    ("working", 6, True, None, None),
    ("needs_you", 3, True, None, None),
    ("done", 6, False, "idle", None),
    ("idle", 1, True, None, None),
    ("error", 8, False, None, "last"),
    ("interrupted", 6, False, None, None),
    ("exited", 1, False, None, "last"),
    ("unknown", 1, False, None, "last"),
]

# ---------------------------------------------------------------- icons (8×8, blocked kinds)
ICONS = {
    # speech bubble + "?"
    "question": [
        ".oooooo.",
        "oYYooYYo",
        "oYYYYoYo",
        "oYYYoYYo",
        "oYYYYYYo",
        "oYYYoYYo",
        ".oYooooo",
        "..o.....",
    ],
    # speech bubble + check box (allow?)
    "permission": [
        ".oooooo.",
        "oYYYYYYo",
        "oYooooYo",
        "oYoYoYYo",
        "oYooYoYo",
        "oYYYYYYo",
        ".oYooooo",
        "..o.....",
    ],
    # padlock
    "auth": [
        "..oooo..",
        ".oYooYo.",
        ".oYooYo.",
        "oooooooo",
        "oYYYYYYo",
        "oYYooYYo",
        "oYYYYYYo",
        "oooooooo",
    ],
}

# ---------------------------------------------------------------- UI icons (12×12)
# List board: cream paper, teal bullets, painted lines; "list_open" lifts it and lights the bullets.
UI_LIST = [
    "............",
    ".oooooooooo.",
    "oblllllllldo",
    "obkkbeeeebdo",
    "oblllllllldo",
    "obkkbeeeebdo",
    "oblllllllldo",
    "obkkbeeebbdo",
    "oblllllllldo",
    "obdddddddddo",
    ".oooooooooo.",
    "............",
]


def ui_list_open():
    g = [list(r) for r in UI_LIST]
    g = [g[i + 1] if i + 1 < len(g) else ["."] * 12 for i in range(len(g))]  # lift 1px
    g = [[{"k": "Y"}.get(c, c) for c in row] for row in g]
    return g


# Launch button: cream round token with a teal plus; "launch_open" lifts it and lights the plus.
UI_LAUNCH = [
    "............",
    "...oooooo...",
    "..obllllbo..",
    ".obllkkllbo.",
    ".oblbkkbldo.",
    ".okkkkkkkdo.",
    ".okkkkkkkdo.",
    ".obbbkkbbdo.",
    ".obbbkkbddo.",
    "..odddddddo.",
    "...oooooo...",
    "............",
]


def ui_launch_open():
    g = [list(r) for r in UI_LAUNCH]
    g = [g[i + 1] if i + 1 < len(g) else ["."] * 12 for i in range(len(g))]  # lift 1px
    return [[{"k": "Y"}.get(c, c) for c in row] for row in g]


# Today button: cream clock face with teal hands; "today_open" lifts it and lights the hands.
UI_TODAY = [
    "............",
    "...oooooo...",
    "..obleelbo..",
    ".obllkllbdo.",
    ".obllkllbdo.",
    ".oellkllbeo.",
    ".obllkkkkdo.",
    ".obbbbbbbdo.",
    ".obbbbbbddo.",
    "..odddeddo..",
    "...oooooo...",
    "............",
]


def ui_today_open():
    g = [list(r) for r in UI_TODAY]
    g = [g[i + 1] if i + 1 < len(g) else ["."] * 12 for i in range(len(g))]  # lift 1px
    return [[{"k": "Y"}.get(c, c) for c in row] for row in g]


# Empty island: a deserted atoll (sand, palm, surf) shown when there are no agents.
UI_EMPTY = [
    "............",
    "....kkk.kk..",
    "...kkkkkkkk.",
    "..kk..dk..k.",
    "......d.....",
    ".....d......",
    ".....d......",
    "...oodooo...",
    "..oblllbbo..",
    ".obbbbbbddo.",
    "zzoooooooozz",
    "..zz....zz..",
]


# ---------------------------------------------------------------- island decoration (5×5)
# Twinkling stars for the island's empty space: dot → plus → big plus → plus.
def twinkle(color):
    dot = [".....", ".....", "..C..", ".....", "....."]
    plus = [".....", "..C..", ".CRC.", "..C..", "....."]
    big = ["..C..", "..R..", "CRRRC", "..R..", "..C.."]
    frames = [dot, plus, big, plus]
    return [[[{"C": color, "R": "r"}.get(c, c) for c in row] for row in f] for f in frames]


# ---------------------------------------------------------------- effects (ticket 17, 16×16 overlays)
# Generated with pixelfx core (MIT) by pixelfx/render.mjs from pixelfx/fx/{send,celebrate}.js and
# quantized to PALETTE keys; this script only packs the committed result into the app sheet.
EFFECTS_SRC = HERE / "pixelfx" / "effects.frames.json"


def load_effects():
    data = json.loads(EFFECTS_SRC.read_text())
    tags, tag_meta = [], {}
    for name in ("send", "celebrate"):
        frames = [[list(row) for row in f] for f in data[name]["frames"]]
        assert all(len(f) == S and all(len(r) == S for r in f) for f in frames), f"{name}: frames must be {S}×{S}"
        tags.append((name, frames))
        tag_meta[name] = (data[name]["fps"], False, None, None)
    return tags, tag_meta


# ---------------------------------------------------------------- rendering


def rgba(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


TABLE = {k: rgba(v) for k, v in PALETTE.items()}
TABLE["S"] = rgba(KEY_LIGHT)
TABLE["s"] = rgba(KEY_DARK)


def draw(grids, size):
    img = Image.new("RGBA", (size * len(grids), size), (0, 0, 0, 0))
    px = img.load()
    for i, g in enumerate(grids):
        for y in range(size):
            for x in range(size):
                ch = g[y][x]
                if ch != ".":
                    assert ch in TABLE, f"unknown pixel key {ch!r}"
                    px[i * size + x, y] = TABLE[ch]
    return img


def write_sheet(name, tag_frames, tag_meta, size):
    grids = [g for _, frames in tag_frames for g in frames]
    img = draw(grids, size)
    img.save(OUT / f"{name}.png")
    frames, tags, index = [], [], 0
    for tag, tframes in tag_frames:
        fps, loop, nxt, hold = tag_meta[tag]
        start = index
        for _ in tframes:
            frames.append({"frame": {"x": index * size, "y": 0, "w": size, "h": size}, "duration": round(1000 / fps)})
            index += 1
        entry = {"name": tag, "from": start, "to": index - 1, "direction": "forward", "loop": loop}
        if nxt:
            entry["next"] = nxt
        if hold:
            entry["hold"] = hold
        tags.append(entry)
    doc = {"frames": frames, "meta": {
        "app": "atoll art/final/make_sprites.py (B / Toy Chunky)",
        "image": f"{name}.png",
        "size": {"w": img.width, "h": img.height},
        "frameSize": {"w": size, "h": size},
        "pivot": {"x": size // 2, "y": size - 1},
        "accessoryKey": KEY_LIGHT.lower(),
        "accessoryKeyDark": KEY_DARK.lower(),
        "frameTags": tags,
    }}
    (OUT / f"{name}.json").write_text(json.dumps(doc, indent=1) + "\n")
    return img


def recolor(img, indiv):
    out = img.copy()
    px = out.load()
    light, dark = rgba(indiv[0]), rgba(indiv[1])
    for y in range(out.height):
        for x in range(out.width):
            if px[x, y] == TABLE["S"]:
                px[x, y] = light
            elif px[x, y] == TABLE["s"]:
                px[x, y] = dark
    return out


def on_black(img):
    bg = Image.new("RGBA", img.size, (0, 0, 0, 255))
    bg.alpha_composite(img)
    return bg


def scale(img, n):
    return img.resize((img.width * n, img.height * n), Image.NEAREST)


def preview(sheets, path):
    """QA sheet: every tag of every appearance at 8× on black, one row per appearance."""
    rows = [on_black(recolor(img, INDIVIDUALS[i % len(INDIVIDUALS)])) for i, img in enumerate(sheets)]
    w = max(r.width for r in rows)
    out = Image.new("RGBA", (w, S * len(rows) + 2 * (len(rows) - 1)), (40, 40, 40, 255))
    for i, r in enumerate(rows):
        out.paste(r, (0, i * (S + 2)))
    scale(out, 8).save(path)


def island_preview(path):
    """1× and 2× island-scale strip: each appearance idle + needs_you, with individual colors."""
    cells = []
    for i, a in enumerate(("claude", "codex", "generic")):
        sheet = Image.open(OUT / f"{a}.png")
        meta = json.loads((OUT / f"{a}.json").read_text())["meta"]["frameTags"]
        for tag in ("idle", "needs_you", "working", "done", "error", "exited", "unknown"):
            t = next(t for t in meta if t["name"] == tag)
            cells.append(recolor(sheet.crop((t["from"] * S, 0, t["from"] * S + S, S)), INDIVIDUALS[i]))
    strip = Image.new("RGBA", (len(cells) * (S + 6) + 14, S + 10), (0, 0, 0, 255))
    for i, c in enumerate(cells):
        strip.alpha_composite(c, (10 + i * (S + 6), 5))
    icons = Image.open(OUT / "icons.png")
    for k in range(3):
        strip.alpha_composite(icons.crop((k * 8, 0, k * 8 + 8, 8)), (10 + (1 + 7 * k) * (S + 6) + 9, 1))
    strip.save(path.with_name("island@1x.png"))
    scale(strip, 2).save(path.with_name("island@2x.png"))
    scale(strip, 6).save(path.with_name("island@6x-inspect.png"))


def check_individuals():
    """Hue distance from the two state colors, so individual ≠ state."""
    import colorsys

    def hue(h):
        r, g, b, _ = rgba(h)
        hh, _, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        return hh * 360, s

    report = []
    for light, dark in INDIVIDUALS:
        h, s = hue(light)
        for state in ("error", "waiting"):
            sh, _ = hue(STATE_COLORS[state])
            d = min(abs(h - sh), 360 - abs(h - sh))
            # Near-grey (silver) has no meaningful hue; skip.
            if s > 0.25:
                assert d >= 40, f"individual {light} too close to {state} ({d:.0f}°)"
        report.append(f"{light}/{dark}")
    return report


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    check_individuals()
    meta = {n: (fps, loop, nxt, hold) for n, fps, loop, nxt, hold in TAGS}
    sheets = []
    for a in ("claude", "codex", "generic"):
        fr = frames_for(a)
        sheets.append(write_sheet(a, [(t[0], fr[t[0]]) for t in TAGS], meta, S))
    write_sheet("icons", [(n, [[list(r) for r in g]]) for n, g in ICONS.items()],
                {n: (1, False, None, "last") for n in ICONS}, 8)
    write_sheet("ui", [("list", [[list(r) for r in UI_LIST]]), ("list_open", [ui_list_open()]),
                       ("launch", [[list(r) for r in UI_LAUNCH]]), ("launch_open", [ui_launch_open()]),
                       ("empty", [[list(r) for r in UI_EMPTY]]),
                       ("today", [[list(r) for r in UI_TODAY]]), ("today_open", [ui_today_open()])],
                {n: (1, False, None, "last")
                 for n in ("list", "list_open", "launch", "launch_open", "empty", "today", "today_open")}, 12)
    write_sheet("deco", [("twinkle", twinkle("l")), ("twinkle_teal", twinkle("k"))],
                {"twinkle": (2, True, None, None), "twinkle_teal": (2, True, None, None)}, 5)
    effects = write_sheet("effects", *load_effects(), S)
    preview(sheets, HERE / "qa-all-tags@8x.png")
    scale(on_black(effects), 8).save(HERE / "qa-effects@8x.png")
    island_preview(HERE / "island.png")
    (HERE / "palette.json").write_text(json.dumps({
        "direction": "B / Toy Chunky",
        "character": {k: PALETTE[k] for k in "odblvekr"},
        "states": STATE_COLORS,
        "dim": {"body": PALETTE["m"], "outline": PALETTE["n"], "sleep": PALETTE["z"]},
        "individuals": [{"light": l, "dark": d} for l, d in INDIVIDUALS],
        "accessoryKeys": {"light": KEY_LIGHT, "dark": KEY_DARK},
    }, indent=2) + "\n")
    print("wrote", sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    main()

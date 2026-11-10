#!/usr/bin/env python3
"""Generate programmatic placeholder sprites in the app's final asset format.

Output (Sources/Atoll/Resources/Sprites/):
  <appearance>.png   transparent sprite sheet, 16x16 frames in one row
  <appearance>.json  Aseprite-style: frames[] (frame rect, duration ms) and
                     meta.frameTags[] (name, from, to, loop, next, hold) + pivot
  icons.png / icons.json   8x8 status bubbles (question, permission, auth)

Pixels in the accessory zone use the key color #FF00FF; the app swaps it for the
agent's individual color at load time. Run: python3 -I scripts/make_placeholder_sprites.py
"""
import json
import os
import sys

from PIL import Image

# Final art lives in Sources/Atoll/Resources/Sprites (art/final/make_sprites.py); placeholders go to build/.
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "placeholder-sprites")
S = 16
KEY = (255, 0, 255, 255)

# Placeholder palette (bright on black; outlines are dark tinted, not black).
C = {
    ".": (0, 0, 0, 0),
    "o": (58, 74, 112, 255),     # outline (dark blue-grey)
    "b": (196, 214, 236, 255),   # body light
    "s": (128, 150, 190, 255),   # body shade
    "e": (120, 240, 255, 255),   # eyes (cyan)
    "k": KEY,                    # accessory (individual color)
    "y": (255, 214, 64, 255),    # waiting yellow (state)
    "r": (255, 84, 84, 255),     # error red (state)
    "g": (120, 236, 140, 255),   # done green
    "w": (255, 255, 255, 255),
    "d": (80, 92, 120, 255),     # dim / sleeping
    "z": (150, 160, 255, 255),   # zzz
    "h": (128, 128, 128, 255),   # grey (unknown)
    "H": (90, 90, 90, 255),
}

# Head templates per appearance: rows 0-7 (head), drawn above a shared body (rows 8-15).
HEADS = {
    # Claude Code: round head, single tall antenna with a ball.
    "claude": [
        ".......k........",
        ".......o........",
        ".....oooo.......",
        "....obbbbo......",
        "...obbbbbbo.....",
        "...obEbbEbo.....",
        "...obbbbbbo.....",
        "....obbbbo......",
    ],
    # Codex: square head, two side bolts.
    "codex": [
        "................",
        "...oooooooo.....",
        "...obbbbbbo.....",
        "..kobbbbbbok....",
        "..kobEbbEbok....",
        "...obbbbbbo.....",
        "...obbbbbbo.....",
        "...oooooooo.....",
    ],
    # Generic: wide dome with a visor.
    "generic": [
        "................",
        "....oooooo......",
        "...obbbbbbo.....",
        "..obbbbbbbbo....",
        "..oEEEEEEEEo....",
        "..obbbbbbbbo....",
        "..obbbbbbbbo....",
        "...oooooooo.....",
    ],
}

BODY = [
    "....okkkkko.....",   # scarf (accessory)
    "...obbbbbbbo....",
    "..oobbbbbbboo...",
    "..osobbbbbosо...".replace("о", "o"),
    "..o.obbbbbo.o...",
    "....osssssо.....".replace("о", "o"),
    "....oo...oo.....",
    "................",
]


def grid(head, body, eyes="e"):
    rows = [r.replace("E", eyes) for r in head] + list(body)
    return [list(r.ljust(S, "."))[:S] for r in rows]


def shift(g, dx=0, dy=0):
    out = [["."] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            ny, nx = y + dy, x + dx
            if 0 <= ny < S and 0 <= nx < S and g[y][x] != ".":
                out[ny][nx] = g[y][x]
    return out


def put(g, x, y, ch):
    if 0 <= x < S and 0 <= y < S:
        g[y][x] = ch


def recolor(g, mapping):
    return [[mapping.get(c, c) for c in row] for row in g]


def arms(g, left_up=False, right_up=False):
    g = [row[:] for row in g]
    if right_up:
        for y in (9, 10, 11):
            g[y][12] = "."
        put(g, 12, 9, "o"); put(g, 13, 8, "o"); put(g, 13, 7, "b")
    if left_up:
        for y in (9, 10, 11):
            g[y][2] = "."
        put(g, 2, 9, "o"); put(g, 1, 8, "o"); put(g, 1, 7, "b")
    return g


def frames_for(head):
    base = grid(head, BODY)
    blink = grid(head, BODY, eyes="o")
    frames = {}
    # starting: materialise from the bottom (4, once)
    frames["starting"] = []
    for i, rows in enumerate((4, 8, 12, 16)):
        f = [row[:] if y >= S - rows else ["."] * S for y, row in enumerate(base)]
        frames["starting"].append(f)
    # working: bob + typing arms (4, loop)
    frames["working"] = [base, shift(arms(base, right_up=True), 0, -1), base, shift(arms(base, left_up=True), 0, -1)]
    # needs you: raise hand, wave (4, loop); eyes yellow
    raised = recolor(arms(base, right_up=True), {"e": "y"})
    frames["needs_you"] = [raised, shift(raised, 0, -1), raised, recolor(arms(blink, right_up=True), {})]
    # done: small celebration — jump with both hands, sparkles (6, once → idle)
    cheer = arms(base, left_up=True, right_up=True)
    sparkle = [row[:] for row in shift(cheer, 0, -2)]
    put(sparkle, 0, 2, "g"); put(sparkle, 14, 1, "g"); put(sparkle, 15, 4, "y")
    frames["done"] = [base, shift(cheer, 0, -1), sparkle, shift(cheer, 0, -1), cheer, base]
    # idle: slow breathing (2, loop)
    frames["idle"] = [base, blink]
    # error: shake, turn red, slump (4, once, hold last)
    red = recolor(base, {"e": "r"})
    slump = shift(recolor(blink, {"o": "o"}), 0, 1)
    slump = recolor(slump, {"e": "r"})
    put(slump, 14, 2, "r"); put(slump, 14, 3, "r"); put(slump, 14, 5, "r")
    frames["error"] = [shift(red, -1, 0), shift(red, 1, 0), red, slump]
    # interrupted: freeze pose (3, once)
    stop = arms(base, left_up=True, right_up=True)
    frames["interrupted"] = [base, stop, base]
    # exited: dim sleeping (1, still)
    sleep = recolor(blink, {"b": "d", "s": "o", "e": "o", "k": "d"})
    put(sleep, 13, 1, "z"); put(sleep, 14, 0, "z")
    frames["exited"] = [sleep]
    # unknown: greyscale + ? (1, still)
    grey = recolor(base, {"b": "h", "s": "H", "e": "H", "k": "H", "o": "H"})
    for (x, y) in ((13, 0), (14, 0), (15, 1), (14, 2), (14, 4)):
        put(grey, x, y, "w")
    frames["unknown"] = [grey]
    return frames


# name: (fps, loop, next, hold)
TAGS = [
    ("starting", 8, False, "working", None),
    ("working", 6, True, None, None),
    ("needs_you", 4, True, None, None),
    ("done", 8, False, "idle", None),
    ("idle", 1, True, None, None),
    ("error", 8, False, None, "last"),
    ("interrupted", 6, False, None, None),
    ("exited", 1, False, None, "last"),
    ("unknown", 1, False, None, "last"),
]

ICONS = {
    "question": [
        ".oooooo.",
        "oyyyyyyo",
        "oyyoooyo",
        "oyyyyoyo",
        "oyyyoyyo",
        "oyyyyyyo",
        ".oyoyoo.",
        "..o.....",
    ],
    "permission": [
        ".oooooo.",
        "oyyyyyyo",
        "oyyooyyo",
        "oyowwoyo",
        "oyowwoyo",
        "oyyyyyyo",
        ".oyoooo.",
        "..o.....",
    ],
    "auth": [
        "..oooo..",
        ".oyyyyo.",
        ".oyoo yo".replace(" ", "o"),
        "oooooooo",
        "oyyyyyyo",
        "oyyooyyo",
        "oyyyyyyo",
        "oooooooo",
    ],
}


def render(frames_grid, size):
    img = Image.new("RGBA", (size * len(frames_grid), size), (0, 0, 0, 0))
    for i, g in enumerate(frames_grid):
        for y in range(size):
            for x in range(size):
                ch = g[y][x] if x < len(g[y]) else "."
                if ch != ".":
                    img.putpixel((i * size + x, y), C[ch])
    return img


def write_sheet(name, ordered, tags_meta, size, extra_meta=None):
    img = render([f for _, frames in ordered for f in frames], size)
    img.save(os.path.join(OUT, f"{name}.png"))
    out_frames, frame_tags, index = [], [], 0
    for tag_name, frames in ordered:
        meta = tags_meta.get(tag_name, {})
        duration = int(1000 / meta.get("fps", 4))
        start = index
        for _ in frames:
            out_frames.append({"frame": {"x": index * size, "y": 0, "w": size, "h": size}, "duration": duration})
            index += 1
        tag = {"name": tag_name, "from": start, "to": index - 1, "direction": "forward", "loop": meta.get("loop", True)}
        if meta.get("next"):
            tag["next"] = meta["next"]
        if meta.get("hold"):
            tag["hold"] = meta["hold"]
        frame_tags.append(tag)
    doc = {
        "frames": out_frames,
        "meta": {
            "app": "atoll placeholder generator",
            "image": f"{name}.png",
            "size": {"w": img.width, "h": img.height},
            "frameSize": {"w": size, "h": size},
            "pivot": {"x": size // 2, "y": size - 1},
            "accessoryKey": "#ff00ff",
            "frameTags": frame_tags,
        },
    }
    if extra_meta:
        doc["meta"].update(extra_meta)
    with open(os.path.join(OUT, f"{name}.json"), "w") as fh:
        json.dump(doc, fh, indent=1)


def main():
    os.makedirs(OUT, exist_ok=True)
    tags_meta = {n: {"fps": fps, "loop": loop, "next": nxt, "hold": hold} for n, fps, loop, nxt, hold in TAGS}
    for name, head in HEADS.items():
        frames = frames_for(head)
        ordered = [(t[0], frames[t[0]]) for t in TAGS]
        write_sheet(name, ordered, tags_meta, S)
    icons = [(n, [[c for c in row] for row in g]) for n, g in ICONS.items()]
    write_sheet("icons", [(n, [g]) for n, g in icons], {n: {"fps": 1, "loop": False, "hold": "last"} for n, _ in icons}, 8)
    print("wrote", sorted(os.listdir(OUT)), file=sys.stderr)


if __name__ == "__main__":
    main()

#!/usr/bin/env node
// Render Atoll's overlay effects with pixelfx core and quantize them to the Atoll palette.
//
//   ./fetch.sh && node render.mjs
//
// Writes effects.frames.json next to this file: { tag: { fps, frames: [16 rows of palette keys] } }.
// make_sprites.py reads it to build Sources/Atoll/Resources/Sprites/effects.{png,json}, so the app
// resources keep a single writer and regenerating sprites does not need Node.

import { existsSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CORE = join(HERE, "vendor", "pixelfx", "src", "core", "index.js");
if (!existsSync(CORE)) {
  console.error("pixelfx not found: run ./fetch.sh first");
  process.exit(1);
}
const { createFrame, clearFrame, createFx, composite } = await import(CORE);

// Atoll palette keys an effect may land on (subset of PALETTE in make_sprites.py)
const KEYS = { o: "#7A3F6E", k: "#7FD6C6", l: "#FFF8EC", r: "#FFFFFF" };
const RGB = Object.entries(KEYS).map(([k, h]) => [k, [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16))]);
const ALPHA_CUTOFF = 128;

function nearest(r, g, b) {
  let best = null, bd = Infinity;
  for (const [k, [R, G, B]] of RGB) {
    const d = (r - R) ** 2 + (g - G) ** 2 + (b - B) ** 2;
    if (d < bd) (bd = d), (best = k);
  }
  return best;
}

async function render(name) {
  const mod = await import(join(HERE, "fx", `${name}.js`));
  const { size: [W, H], origin: [OX, OY], fps, duration } = mod.meta;
  const fx = createFx(mod, { x: OX, y: OY });
  const frame = createFrame(W, H), rgba = new Uint8ClampedArray(W * H * 4);
  const n = Math.round(duration * fps) + 1, frames = [];
  for (let i = 0; i < n; i++) {
    if (i > 0) fx.update(1 / fps);
    clearFrame(frame);
    fx.draw(frame);
    composite(frame, rgba, null);
    const rows = [];
    for (let y = 0; y < H; y++) {
      let row = "";
      for (let x = 0; x < W; x++) {
        const j = (y * W + x) * 4;
        row += rgba[j + 3] < ALPHA_CUTOFF ? "." : nearest(rgba[j], rgba[j + 1], rgba[j + 2]);
      }
      rows.push(row);
    }
    frames.push(rows);
  }
  // one-shots end empty in pixelfx; drop trailing empty frames so the overlay ends on its last visible frame
  const empty = (f) => f.every((r) => /^\.*$/.test(r));
  while (frames.length > 1 && empty(frames.at(-1))) frames.pop();
  if (frames.some(empty)) throw new Error(`${name}: empty frame in the middle`);
  return { fps, frames };
}

const out = {};
for (const name of ["send", "celebrate"]) out[name] = await render(name);
const file = join(HERE, "effects.frames.json");
writeFileSync(file, JSON.stringify(out, null, 1) + "\n");
for (const [k, v] of Object.entries(out)) console.log(`${k}: ${v.frames.length} frames @ ${v.fps} fps`);
console.log("->", file);

// Message fly-out for Atoll's 16x16 overlay layer, written against pixelfx core (MIT).
// Local coordinates are the overlay's pixels; the robot's right hand is around (12, 10).
import { clamp, ease, hex, lerp } from "../vendor/pixelfx/src/core/index.js";

export const meta = {
  name: "Atoll send",
  desc: "A tiny message card pops off the right hand, swings up and out of the top-right corner on a curve, leaving a short teal trail.",
  tags: ["ui", "message", "send", "one-shot"],
  size: [16, 16],
  origin: [0, 0],
  duration: 0.58,
  loop: false,
  fps: 12,
  bg: "dark",
  // palette: [outline plum, teal, cream, white] — Atoll palette keys o, k, l, r
  options: { palette: ["#7A3F6E", "#7FD6C6", "#FFF8EC", "#FFFFFF"] },
};

// quadratic bezier from the hand, out along the right side of the head (x > 13), past the top-right edge
const P0 = [12, 10], P1 = [15.5, 5], P2 = [19, -2];
function at(u) {
  const a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, c = u * u;
  return [a * P0[0] + b * P1[0] + c * P2[0], a * P0[1] + b * P1[1] + c * P2[1]];
}

export function draw(p, t, o) {
  const [plum, teal, cream, white] = o.palette.map(hex);
  const D = meta.duration, u = ease.inOutQuad(clamp(t / (D * 0.85)));
  // launch puff at the hand
  if (t < 0.09) {
    p.px(P0[0] + 1, P0[1], white);
    p.px(P0[0] + 1, P0[1] - 1, cream);
  }
  // trail: two samples behind the card, the nearer one teal, the farther one plum
  for (const [lag, c] of [[0.12, teal], [0.24, plum]]) {
    const v = u - lag;
    if (v <= 0 || u >= 1) continue;
    const [x, y] = at(v);
    p.px(Math.floor(x), Math.floor(y) + 1, c);
  }
  if (u >= 1) return;
  // the card: 3x2 cream with a plum fold, it tilts flat to upright as it climbs
  const [x, y] = at(u), X = Math.floor(x), Y = Math.floor(y);
  const w = Math.round(lerp(3, 2, u));
  p.rect(X - 1, Y, w, 2, cream);
  p.px(X - 1, Y, plum);
  if (u < 0.35) p.px(X - 1 + w, Y, white);
}

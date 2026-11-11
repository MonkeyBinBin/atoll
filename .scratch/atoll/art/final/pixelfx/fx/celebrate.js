// Done celebration for Atoll's 16x16 overlay layer, written against pixelfx core (MIT).
// Local coordinates are the overlay's pixels: (0,0) top-left, the robot's head top sits near y = 1.
import { Rng, TAU, clamp, ease, hex } from "../vendor/pixelfx/src/core/index.js";

export const meta = {
  name: "Atoll celebrate",
  desc: "A white pop on the row above the head; teal sparks skim out over the head, turn cream and white once clear of it, droop down both sides, twinkle and wink out.",
  tags: ["ui", "celebration", "sparkle", "one-shot"],
  size: [16, 16],
  origin: [0, 0],
  duration: 0.75,
  loop: false,
  fps: 12,
  bg: "dark",
  // palette: [teal, cream, white] — Atoll palette keys k, l, r
  options: { palette: ["#7FD6C6", "#FFF8EC", "#FFFFFF"], seed: 4 },
};

// the head is centred between columns 7 and 8 and spans x 2..13 from y 1 down; row 0 is clear.
// The right half is simulated and mirrored (x -> 15 - x). Over the cream head only teal reads, so a
// spark stays teal until it is past the head's edge.
const CX = 8, CY = 0, HEAD_EDGE = 13;

export function create(o) {
  const [teal, cream, white] = o.palette.map(hex), R = new Rng(o.seed);
  // angles below the horizontal (y grows down, row 0 is the top edge): a flat wide spark, a shallow and a steep one
  const sparks = [[0, 21, cream, true], [-22, 19, white, false], [-48, 17, cream, false]].map(([deg, sp, c, big]) => {
    const a = (-deg * Math.PI) / 180 + R.range(-0.05, 0.05);
    return { x: CX + 0.5, y: CY + 0.5, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, c, big, life: R.range(0.62, 0.7), ph: R.range(0, TAU) };
  });
  let t = 0;
  const both = (p, x, y, c) => (p.px(x, y, c), p.px(15 - x, y, c));
  return {
    update(dt) {
      t += dt;
      for (const s of sparks) {
        s.vx -= s.vx * 3 * dt;
        s.vy -= s.vy * 3 * dt;
        s.vy += 14 * dt;
        s.x += s.vx * dt;
        s.y += s.vy * dt;
      }
    },
    draw(p) {
      // the pop: a 2-wide flash over the head with cream arms, then a single white pair
      if (t < 0.09) {
        both(p, CX, CY, white);
        both(p, CX + 1, CY, teal);
      } else if (t < 0.17) both(p, CX, CY, white);
      for (const s of sparks) {
        const k = clamp(1 - t / s.life);
        if (k <= 0 || t < 0.04) continue;
        // late in life, blink out on alternate frames
        if (k < 0.3 && Math.sin(t * 40 + s.ph) < 0) continue;
        const X = Math.floor(s.x), Y = Math.floor(s.y);
        const clear = X > HEAD_EDGE || Y < 1;
        both(p, X, Y, !clear ? teal : k > 0.75 ? white : s.c);
        // the big one shows a small cross while it is fast and clear of the head
        if (s.big && clear && ease.outQuad(k) > 0.6)
          for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            const x = X + dx, y = Y + dy;
            if (x > HEAD_EDGE || y < 1) both(p, x, y, s.c);
          }
      }
    },
  };
}

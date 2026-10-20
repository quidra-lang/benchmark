import type { Point, Trig } from './pgm_io.ts';
export interface CircleLayer {
  radius: number;
  offsets: Point[];
  counts: Int32Array;
}
export interface CirclePeak extends Point {
  radius: number;
  votes: number;
  points: number;
  offsets: Point[];
}
export interface LinePeak {
  theta: number;
  rho: number;
  votes: number;
}
export const rho = (p: Point, t: number, trig: Trig, step: number) =>
  Math.floor((p.x * trig.cos[t] + p.y * trig.sin[t]) / (16384 * step));
export function circlePoints(radius: number) {
  const points = new Map<string, Point>();
  let a = radius;
  let b = 0;
  let error = 1 - radius;
  while (a >= b) {
    for (const [x, y] of [
      [a, b],
      [b, a],
      [-b, a],
      [-a, b],
      [-a, -b],
      [-b, -a],
      [b, -a],
      [a, -b],
    ]) {
      points.set(`${x},${y}`, { x, y });
    }
    b++;
    if (error < 0) error += 2 * b + 1;
    else {
      a--;
      error += 2 * (b - a) + 1;
    }
  }
  return [...points.values()];
}
export function circleVotes(edges: Uint8Array, w: number, h: number, min: number, max: number) {
  const pixels: Point[] = [];
  for (let i = 0; i < edges.length; i++) {
    if (edges[i]) pixels.push({ x: i % w, y: Math.floor(i / w) });
  }
  const layers: CircleLayer[] = [];
  for (let radius = min; radius <= max; radius++) {
    const offsets = circlePoints(radius);
    const counts = new Int32Array(w * h);
    for (const p of pixels) {
      for (const o of offsets) {
        const x = p.x + o.x;
        const y = p.y + o.y;
        if (x >= 0 && x < w && y >= 0 && y < h) counts[y * w + x]++;
      }
    }
    layers.push({ radius, offsets, counts });
  }
  return layers;
}
export function circlePeaks(layers: CircleLayer[], w: number, h: number, percent: number) {
  const peaks: CirclePeak[] = [];
  let candidates = 0;
  for (let k = 0; k < layers.length; k++) {
    for (let i = 0; i < layers[k].counts.length; i++) {
      const layer = layers[k];
      const votes = layer.counts[i];
      const points = layer.offsets.length;
      if (100 * votes < percent * points) continue;
      candidates++;
      const x = i % w;
      const y = Math.floor(i / w);
      let peak = true;
      for (let o = Math.max(0, k - 2); o <= Math.min(layers.length - 1, k + 2) && peak; o++) {
        for (let ny = Math.max(0, y - 2); ny <= Math.min(h - 1, y + 2) && peak; ny++) {
          for (let nx = Math.max(0, x - 2); nx <= Math.min(w - 1, x + 2); nx++) {
            const next = ny * w + nx;
            if (o === k && next === i) continue;
            const lhs = votes * layers[o].offsets.length;
            const rhs = layers[o].counts[next] * points;
            const earlier = o < k || (o === k && next < i);
            if (lhs < rhs || (lhs === rhs && earlier)) {
              peak = false;
              break;
            }
          }
        }
      }
      if (peak) peaks.push({ radius: layer.radius, x, y, votes, points, offsets: layer.offsets });
    }
  }
  return { candidates, peaks };
}
export function lineVotes(pixels: Point[], trig: Trig, step: number) {
  return Array.from({ length: 180 }, (_, t) => {
    const counts = new Map<number, number>();
    for (const p of pixels) {
      const r = rho(p, t, trig, step);
      counts.set(r, (counts.get(r) ?? 0) + 1);
    }
    return counts;
  });
}
export function linePeaks(votes: Map<number, number>[], threshold: number) {
  const peaks: LinePeak[] = [];
  for (let t = 0; t < 180; t++) {
    for (const [r, count] of votes[t]) {
      if (count < threshold) continue;
      let peak = true;
      for (let a = Math.max(0, t - 2); a <= Math.min(179, t + 2) && peak; a++) {
        for (let b = r - 2; b <= r + 2; b++) {
          if (a === t && b === r) continue;
          const other = votes[a].get(b) ?? 0;
          const earlier = a < t || (a === t && b < r);
          if (count < other || (count === other && earlier)) {
            peak = false;
            break;
          }
        }
      }
      if (peak) peaks.push({ theta: t, rho: r, votes: count });
    }
  }
  return peaks;
}

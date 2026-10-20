import type { Point, Kernel, Fit, Estimate } from './dataset.ts';
export interface KernelEstimate extends Estimate {
  diagonal: number | null;
}
export interface KernelFit extends Fit {
  kind: 'kernel';
}
const CONSTANTS = { epanechnikov: 0.75, biweight: 0.9375, triweight: 1.09375 };
export function kernel(name: Kernel, u: number): number {
  const t = 1 - u * u;
  return name === 'epanechnikov'
    ? 0.75 * t
    : name === 'biweight'
      ? 0.9375 * t * t
      : 1.09375 * t * t * t;
}
export function estimate(
  points: Point[],
  kind: 'nw' | 'll',
  name: Kernel,
  bandwidth: number,
  position: number,
): KernelEstimate {
  const x0 = position / 100;
  const h = bandwidth / 100;
  const used: { index: number; d: number; weight: number }[] = [];
  let s0 = 0;
  let s1 = 0;
  let s2 = 0;
  let t0 = 0;
  let t1 = 0;
  points.forEach((p, j) => {
    if (Math.abs(p.X - position) >= bandwidth) return;
    const d = p.x - x0;
    const w = kernel(name, d / h);
    used.push({ index: j, d, weight: w });
    s0 += w;
    t0 += w * p.y;
    if (kind === 'll') {
      s1 += w * d;
      s2 += w * d * d;
      t1 += w * d * p.y;
    }
  });
  if (used.length < (kind === 'nw' ? 1 : 2)) return { value: null, weights: null, diagonal: null };
  const weights: number[] = Array(points.length).fill(0);
  if (kind === 'nw') {
    for (const p of used) weights[p.index] = p.weight / s0;
    return { value: t0 / s0, weights, diagonal: CONSTANTS[name] / s0 };
  }
  const q = s0 * s2 - s1 * s1;
  for (const p of used) weights[p.index] = (p.weight * (s2 - s1 * p.d)) / q;
  return { value: (s2 * t0 - s1 * t1) / q, weights, diagonal: (CONSTANTS[name] * s2) / q };
}
export function fit(
  points: Point[],
  kind: 'nw' | 'll',
  name: Kernel,
  bandwidth: number,
): KernelFit {
  const at = (position: number) => estimate(points, kind, name, bandwidth, position);
  const estimates = points.map((p) => at(p.X));
  if (estimates.some((e) => e.value === null)) {
    return { kind: 'kernel', yhat: null, lev: null, edf: null, at };
  }
  const lev = estimates.map((e) => e.diagonal!);
  let edf = 0;
  for (const v of lev) edf += v;
  return { kind: 'kernel', yhat: estimates.map((e) => e.value!), lev, edf, at };
}

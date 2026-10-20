import type { Minstd } from './minstd.ts';

export function sum(values: number[]): number {
  let total = 0;
  for (const value of values) total += value;
  return total;
}
export function sorted(values: number[]): number[] {
  return values.slice().sort((a, b) => a - b);
}
export function mean(values: number[]): number {
  return sum(values) / (100 * values.length);
}
export function Md(values: number[]): number {
  const order = sorted(values);
  return order[Math.floor((order.length - 1) / 2)] + order[Math.floor(order.length / 2)];
}
export function med(values: number[]): number {
  return Md(values) / 200;
}
export function trim(values: number[]): number {
  const order = sorted(values);
  const t = Math.floor(values.length / 10);
  return sum(order.slice(t, values.length - t)) / (100 * (values.length - 2 * t));
}
export function moments(values: number[]) {
  const center = mean(values);
  let second = 0;
  let third = 0;
  let fourth = 0;
  for (const value of values) {
    const e = value / 100 - center;
    second += e * e;
    third += e * e * e;
    fourth += e * e * e * e;
  }
  return {
    sd: Math.sqrt(second / (values.length - 1)),
    m2: second / values.length,
    m3: third / values.length,
    m4: fourth / values.length,
  };
}
export function sd(values: number[]): number {
  return moments(values).sd;
}
export function mad(values: number[]): number {
  const median = Md(values);
  return Md(values.map((value) => Math.abs(2 * value - median))) / 400;
}
export function Qn(values: number[], percentile: number): number {
  const order = sorted(values);
  const u = (values.length - 1) * percentile;
  const j = Math.floor(u / 100);
  const f = u - 100 * j;
  return 100 * order[j] + (f === 0 ? 0 : f * (order[j + 1] - order[j]));
}
export function wins(values: number[]): number[] {
  const order = sorted(values);
  const t = Math.floor(values.length / 10);
  return values.map((value) => Math.min(Math.max(value, order[t]), order[values.length - t - 1]));
}
export function mdiff(x: number[], y: number[]): number {
  return (y.length * sum(x) - x.length * sum(y)) / (100 * x.length * y.length);
}
export function mratio(x: number[], y: number[]): number {
  return Md(x) / Md(y);
}
export function hl(x: number[], y: number[]): number {
  const differences: number[] = [];
  for (const first of x) for (const second of y) differences.push(first - second);
  return Md(differences) / 200;
}
export function sp(x: number[], y: number[]): number {
  const sx = sd(x);
  const sy = sd(y);
  return Math.sqrt(
    ((x.length - 1) * sx * sx + (y.length - 1) * sy * sy) / (x.length + y.length - 2),
  );
}
export function cd(x: number[], y: number[]): number {
  return mdiff(x, y) / sp(x, y);
}
export function corr(x: number[], y: number[]): number {
  const mx = mean(x);
  const my = mean(y);
  let cross = 0;
  let first = 0;
  let second = 0;
  for (let j = 0; j < x.length; j++) {
    const e = x[j] / 100 - mx;
    const f = y[j] / 100 - my;
    cross += e * f;
    first += e * e;
    second += f * f;
  }
  return cross / Math.sqrt(first * second);
}
export function drawIndices(size: number, rng: Minstd): number[] {
  return Array.from({ length: size }, () => rng.below(size));
}
export function ordinaryIndices(size: number, count: number, rng: Minstd): number[][] {
  return Array.from({ length: count }, () => drawIndices(size, rng));
}
export function balancedIndices(size: number, count: number, rng: Minstd): number[][] {
  const indices = Array.from({ length: size * count }, (_, i) => i % size);
  rng.shuffle(indices);
  return Array.from({ length: count }, (_, r) => indices.slice(r * size, (r + 1) * size));
}
export function without(values: number[], index: number): number[] {
  return values.filter((_, j) => j !== index);
}
export function meanAndSe(values: number[]) {
  const average = sum(values) / values.length;
  let squared = 0;
  for (const value of values) {
    const e = value - average;
    squared += e * e;
  }
  return { average, se: Math.sqrt(squared / (values.length - 1)) };
}
export function Phi(x: number): number {
  if (x < 0) return 1 - Phi(-x);
  const eta = 1 / (1 + 0.2316419 * x);
  const psi =
    eta *
    (0.31938153 +
      eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
  return 1 - 0.3989422804014327 * Math.exp(-(x * x) / 2) * psi;
}
export function PhiInv(p: number): number {
  if (p > 0.5) return -PhiInv(1 - p);
  const eta = Math.sqrt(-2 * Math.log(p));
  return -(
    eta -
    (2.515517 + eta * (0.802853 + eta * 0.010328)) /
      (1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308)))
  );
}

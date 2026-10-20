import type { Data, TrainingRating } from './ratings.ts';
import { trainingRmse } from './evaluation.ts';
export interface LogEntry { method: 'BASELINE' | 'SVD' | 'ALS'; epoch: number; rmse: number }
export class Random {
  constructor(private state: number) {}
  next(): number { this.state = 48271 * this.state % 2147483647; return this.state; }
  factor(): number { return (this.next() % 2001 - 1000) / 10000; }
}
export function dot(a: number[], b: number[]): number { let total = 0; for (let f = 0; f < a.length; f++) total += a[f] * b[f]; return total; }
export function trainSvd(data: Data) {
  const s = data.settings, random = new Random(s.seed), userFactors = data.users.map(() => Array.from({ length: s.factors }, () => random.factor())), itemFactors = data.items.map(() => Array.from({ length: s.factors }, () => random.factor()));
  const userBias = data.users.map(() => 0), itemBias = data.items.map(() => 0), order = data.train.map((_, i) => i), history: LogEntry[] = [];
  const predict = (u: number, i: number) => ((data.mean + userBias[u]) + itemBias[i]) + dot(userFactors[u], itemFactors[i]);
  for (let epoch = 1; epoch <= s.epochs; epoch++) {
    for (let t = order.length - 1; t >= 1; t--) { const y = random.next() % (t + 1); [order[t], order[y]] = [order[y], order[t]]; }
    for (const index of order) {
      const { u, i, rating } = data.train[index], e = rating - predict(u, i);
      userBias[u] += s.learningRate * (e - s.regularization * userBias[u]); itemBias[i] += s.learningRate * (e - s.regularization * itemBias[i]);
      for (let f = 0; f < s.factors; f++) { const a = userFactors[u][f], b = itemFactors[i][f]; userFactors[u][f] = a + s.learningRate * (e * b - s.regularization * a); itemFactors[i][f] = b + s.learningRate * (e * a - s.regularization * b); }
    }
    history.push({ method: 'SVD', epoch, rmse: trainingRmse(data.train, predict) });
  }
  return { userFactors, itemFactors, userBias, itemBias, predict, history };
}
export function solve(a: number[][], right: number[]): number[] {
  const n = right.length, lower: number[][] = Array.from({ length: n }, () => Array(n).fill(0));
  for (let i = 0; i < n; i++) for (let j = 0; j <= i; j++) { let total = 0; for (let t = 0; t < j; t++) total += lower[i][t] * lower[j][t]; const v = a[i][j] - total; lower[i][j] = i === j ? Math.sqrt(v) : v / lower[j][j]; }
  const z: number[] = Array(n).fill(0), result: number[] = Array(n).fill(0);
  for (let i = 0; i < n; i++) { let total = 0; for (let t = 0; t < i; t++) total += lower[i][t] * z[t]; z[i] = (right[i] - total) / lower[i][i]; }
  for (let i = n - 1; i >= 0; i--) { let total = 0; for (let t = i + 1; t < n; t++) total += lower[t][i] * result[t]; result[i] = (z[i] - total) / lower[i][i]; }
  return result;
}
export function trainAls(data: Data, baseline: (u: number, i: number) => number) {
  const s = data.settings, random = new Random(s.seed), itemFactors = data.items.map(() => Array.from({ length: s.factors }, () => random.factor())), userFactors: number[][] = Array(data.users.length);
  const residual = data.train.map(r => r.rating - baseline(r.u, r.i)), history: LogEntry[] = [];
  function fit(entries: TrainingRating[], factors: number[][], key: 'u' | 'i'): number[] {
    const a: number[][] = Array.from({ length: s.factors }, () => Array(s.factors).fill(0)), w: number[] = Array(s.factors).fill(0);
    for (let f = 0; f < s.factors; f++) {
      for (let h = 0; h < s.factors; h++) { let total = 0; for (const r of entries) total += factors[r[key]][f] * factors[r[key]][h]; a[f][h] = total; }
      a[f][f] += s.alsReg * entries.length; let total = 0; for (const r of entries) total += residual[r.index] * factors[r[key]][f]; w[f] = total;
    }
    return solve(a, w);
  }
  const predict = (u: number, i: number) => baseline(u, i) + dot(userFactors[u], itemFactors[i]);
  for (let epoch = 1; epoch <= s.alsIterations; epoch++) {
    data.users.forEach((u, index) => { userFactors[index] = fit(u.entries, itemFactors, 'i'); });
    data.items.forEach((i, index) => { itemFactors[index] = fit(i.entries, userFactors, 'u'); });
    history.push({ method: 'ALS', epoch, rmse: trainingRmse(data.train, predict) });
  }
  return { userFactors, itemFactors, predict, history };
}

import type { ValuesRow, BinaryRow, MultiRow } from './dataset.ts';
export class Stump {
  constructor(readonly feature: number, readonly thresholds: number[], readonly values: number[]) {}
  output(values: number[]): number {
    let bin = 0;
    for (const threshold of this.thresholds) if (values[this.feature] > threshold) bin++;
    return this.values[bin];
  }
}
export function prepare(rows: ValuesRow[]) {
  return rows[0].values.map((_, feature) => {
    const order = rows.map((_, i) => i).sort((a, b) => rows[a].values[feature] - rows[b].values[feature] || a - b);
    const groups: number[][] = [], distinct: number[] = [];
    for (const i of order) {
      const value = rows[i].values[feature];
      if (!distinct.length || distinct[distinct.length - 1] !== value) { distinct.push(value); groups.push([]); }
      groups[groups.length - 1].push(i);
    }
    const thresholds = [distinct[0] - 1];
    for (let i = 1; i < distinct.length; i++) thresholds.push((distinct[i - 1] + distinct[i]) / 2);
    return { feature, order, groups, thresholds };
  });
}
type Plan = ReturnType<typeof prepare>[number];
export function choose<T extends { error: number }>(candidates: T[]): T {
  let minimum = candidates[0].error;
  for (const candidate of candidates) if (candidate.error < minimum) minimum = candidate.error;
  return candidates.find(c => c.error <= minimum + 1e-9)!;
}
export function discreteSearch(rows: BinaryRow[], weights: number[], plans: Plan[]) {
  let positive = 0, negative = 0;
  rows.forEach((row, i) => { positive += row.label === 1 ? weights[i] : 0; negative += row.label === -1 ? weights[i] : 0; });
  const candidates: { feature: number; threshold: number; polarity: number; error: number }[] = [];
  for (const plan of plans) {
    let lp = 0, ln = 0;
    for (let k = 0; k < plan.thresholds.length; k++) {
      if (k > 0) for (const i of plan.groups[k - 1]) { lp += rows[i].label === 1 ? weights[i] : 0; ln += rows[i].label === -1 ? weights[i] : 0; }
      candidates.push({ feature: plan.feature, threshold: plan.thresholds[k], polarity: 1, error: lp + (negative - ln) },
        { feature: plan.feature, threshold: plan.thresholds[k], polarity: -1, error: ln + (positive - lp) });
    }
  }
  return choose(candidates);
}
export function regressionSearch(rows: ValuesRow[], targets: number[], weights: number[], plans: Plan[]) {
  let weight = 0, total = 0, squares = 0;
  for (let i = 0; i < rows.length; i++) { weight += weights[i]; total += weights[i] * targets[i]; squares += weights[i] * targets[i] * targets[i]; }
  const candidates: { stump: Stump; error: number }[] = [];
  for (const plan of plans) {
    let lw = 0, ls = 0;
    for (let k = 0; k < plan.thresholds.length; k++) {
      if (k > 0) for (const i of plan.groups[k - 1]) { lw += weights[i]; ls += weights[i] * targets[i]; }
      const rw = weight - lw, rs = total - ls, left = k === 0 ? 0 : ls / lw;
      const gain = k === 0 ? rs * rs / rw : ls * ls / lw + rs * rs / rw;
      candidates.push({ stump: new Stump(plan.feature, [plan.thresholds[k]], [left, rs / rw]), error: squares - gain });
    }
  }
  return choose(candidates);
}
export function largestIndex(values: number[]): number {
  let best = 0;
  for (let i = 1; i < values.length; i++) if (values[i] > values[best]) best = i;
  return best;
}
export function multiclassSearch(rows: MultiRow[], weights: number[], plans: Plan[], classes: number) {
  let total = 0;
  const totals = Array<number>(classes).fill(0), candidates: { stump: Stump; error: number }[] = [];
  rows.forEach((row, i) => { total += weights[i]; for (let c = 0; c < classes; c++) totals[c] += row.category === c + 1 ? weights[i] : 0; });
  for (const plan of plans) {
    const left = Array<number>(classes).fill(0);
    for (let k = 0; k < plan.thresholds.length; k++) {
      if (k > 0) for (const i of plan.groups[k - 1]) for (let c = 0; c < classes; c++) left[c] += rows[i].category === c + 1 ? weights[i] : 0;
      const right = totals.map((v, c) => v - left[c]), a = largestIndex(left), b = largestIndex(right);
      candidates.push({ stump: new Stump(plan.feature, [plan.thresholds[k]], [a + 1, b + 1]), error: total - (left[a] + right[b]) });
    }
  }
  return choose(candidates);
}
export function realPlans(rows: ValuesRow[], bins: number) {
  return prepare(rows).map(plan => {
    const cuts: number[] = [];
    for (let b = 1; b < bins; b++) {
      const r = Math.floor(b * rows.length / bins);
      cuts.push((rows[plan.order[r - 1]].values[plan.feature] + rows[plan.order[r]].values[plan.feature]) / 2);
    }
    return { feature: plan.feature, cuts, assignments: rows.map(row => cuts.filter(c => c < row.values[plan.feature]).length) };
  });
}
export function realSearch(rows: BinaryRow[], weights: number[], plans: ReturnType<typeof realPlans>, bins: number) {
  return choose(plans.map(plan => {
    const positive = Array<number>(bins).fill(0), negative = Array<number>(bins).fill(0);
    rows.forEach((row, i) => { const bin = plan.assignments[i]; if (row.label === 1) positive[bin] += weights[i]; else negative[bin] += weights[i]; });
    let overlap = 0;
    for (let b = 0; b < bins; b++) overlap += Math.sqrt(positive[b] * negative[b]);
    return { feature: plan.feature, cuts: plan.cuts, positive, negative, error: 2 * overlap };
  }));
}

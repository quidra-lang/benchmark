import type { TransitionModel } from './environment.ts';
export function floorDivide(n: number, d: number): number {
  const a = BigInt(n);
  const b = BigInt(d);
  let q = a / b;
  if (a < 0n && a % b !== 0n) q--;
  return Number(q);
}
export function firstMaximum(values: number[]): number {
  let best = 0;
  for (let a = 1; a < values.length; a++) if (values[a] > values[best]) best = a;
  return best;
}
export function bellman(
  model: TransitionModel,
  values: number[],
  state: number,
  action: number,
  gamma: number,
): number {
  let total = 0;
  for (const t of model.transitions[state][action]) {
    total +=
      t.weight * (10000 * t.reward + (t.next < 0 ? 0 : floorDivide(gamma * values[t.next], 100)));
  }
  return floorDivide(total, model.denominator);
}
export function rowValues(
  model: TransitionModel,
  values: number[],
  state: number,
  gamma: number,
): number[] {
  return [0, 1, 2, 3].map((a) => bellman(model, values, state, a, gamma));
}
export function actionValues(model: TransitionModel, values: number[], gamma: number): number[][] {
  return values.map((_, s) => rowValues(model, values, s, gamma));
}
export function greedyPolicy(table: number[][]): number[] {
  return table.map(firstMaximum);
}
export function valueIteration(model: TransitionModel, gamma: number, theta: number) {
  let values: number[] = Array(model.world.states.length).fill(0);
  const changes: number[] = [];
  while (true) {
    const next = actionValues(model, values, gamma).map((row) => row[firstMaximum(row)]);
    let delta = 0;
    for (let s = 0; s < values.length; s++) delta = Math.max(delta, Math.abs(next[s] - values[s]));
    values = next;
    changes.push(delta);
    if (delta <= theta) return { values, changes, iterations: changes.length };
  }
}
export function inPlaceValueIteration(model: TransitionModel, gamma: number, theta: number) {
  const values: number[] = Array(model.world.states.length).fill(0);
  let iterations = 0;
  while (true) {
    let delta = 0;
    for (let s = 0; s < values.length; s++) {
      const row = rowValues(model, values, s, gamma);
      const next = row[firstMaximum(row)];
      delta = Math.max(delta, Math.abs(next - values[s]));
      values[s] = next;
    }
    iterations++;
    if (delta <= theta) return { values, iterations };
  }
}
export function evaluatePolicy(
  model: TransitionModel,
  policy: number[],
  gamma: number,
  theta: number,
  initial?: number[],
) {
  const values: number[] = initial ? [...initial] : Array(policy.length).fill(0);
  let sweeps = 0;
  while (true) {
    let delta = 0;
    for (let s = 0; s < policy.length; s++) {
      const next = bellman(model, values, s, policy[s], gamma);
      delta = Math.max(delta, Math.abs(next - values[s]));
      values[s] = next;
    }
    sweeps++;
    if (delta <= theta) return { values, sweeps };
  }
}
export function policyIteration(model: TransitionModel, gamma: number, theta: number) {
  let policy: number[] = Array(model.world.states.length).fill(0);
  let values: number[] = Array(policy.length).fill(0);
  const rounds: { number: number; sweeps: number; changed: number; start: number }[] = [];
  while (true) {
    const evaluated = evaluatePolicy(model, policy, gamma, theta, values);
    values = evaluated.values;
    const next = greedyPolicy(actionValues(model, values, gamma));
    const changed = next.filter((a, s) => a !== policy[s]).length;
    rounds.push({
      number: rounds.length + 1,
      sweeps: evaluated.sweeps,
      changed,
      start: values[model.world.startIndex],
    });
    policy = next;
    if (!changed) return { values, policy, rounds };
  }
}

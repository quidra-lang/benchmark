import { floorDivide } from './dynamic_programming.ts';
export interface RecordedStep { state: number; action: number; reward: number }
export function discountedReturn(rewards: number[], gamma: number): number {
  let value = 0;
  for (let i = rewards.length - 1; i >= 0; i--) value = 10000 * rewards[i] + floorDivide(gamma * value, 100);
  return value;
}
export class FirstVisit {
  private totals: number[][];
  private counts: number[][];
  constructor(states: number) { this.totals = Array.from({ length: states }, () => Array(4).fill(0)); this.counts = this.totals.map(row => [...row]); }
  update(table: number[][], steps: RecordedStep[], gamma: number): void {
    const first = new Map<number, number>();
    steps.forEach((s, i) => { const key = s.state * 4 + s.action; if (!first.has(key)) first.set(key, i); });
    let value = 0;
    for (let i = steps.length - 1; i >= 0; i--) {
      const { state, action, reward } = steps[i]; value = 10000 * reward + floorDivide(gamma * value, 100);
      if (first.get(state * 4 + action) !== i) continue;
      this.totals[state][action] += value; this.counts[state][action]++;
      table[state][action] = floorDivide(this.totals[state][action], this.counts[state][action]);
    }
  }
}

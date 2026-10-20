import type { Minstd } from './environment.ts';
import { firstMaximum, floorDivide } from './dynamic_programming.ts';
export function choose(table: number[][], state: number, epsilon: number, random: Minstd): number {
  return random.draw() % 1000 < epsilon ? random.draw() % 4 : firstMaximum(table[state]);
}
export function nextValue(table: number[][], state: number, epsilon: number | null = null): number {
  if (state < 0) return 0;
  const row = table[state], max = row[firstMaximum(row)];
  if (epsilon === null) return max;
  let total = 0;
  for (const v of row) total += v;
  return floorDivide(epsilon * total + 4 * (1000 - epsilon) * max, 4000);
}
export function target(reward: number, next: number, future: number, gamma: number): number { return 10000 * reward + (next < 0 ? 0 : floorDivide(gamma * future, 100)); }
export function update(table: number[][], state: number, action: number, reward: number, next: number, future: number, gamma: number, alpha: number): void {
  const old = table[state][action]; table[state][action] = old + floorDivide(alpha * (target(reward, next, future, gamma) - old), 100);
}
interface ModelEntry { state: number; action: number; reward: number; next: number }
export class DynaModel {
  private entries = new Map<number, ModelEntry>();
  private pairs: number[] = [];
  record(state: number, action: number, reward: number, next: number): void {
    const key = state * 4 + action;
    if (!this.entries.has(key)) this.pairs.push(key);
    this.entries.set(key, { state, action, reward, next });
  }
  plan(table: number[][], count: number, gamma: number, alpha: number, random: Minstd): void {
    for (let i = 0; i < count; i++) {
      const e = this.entries.get(this.pairs[random.draw() % this.pairs.length])!;
      update(table, e.state, e.action, e.reward, e.next, nextValue(table, e.next), gamma, alpha);
    }
  }
}

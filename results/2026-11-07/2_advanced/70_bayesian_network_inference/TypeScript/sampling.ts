import { combination } from './learning.ts';
import type { Variable } from './network_io.ts';

export class Minstd {
  constructor(private state: number) {}
  next(): number {
    this.state = (48271 * this.state) % 2147483647;
    return this.state / 2147483647;
  }
}
export function select(probabilities: number[], random: Minstd): number {
  const u = random.next();
  let cumulative = 0;
  for (let state = 0; state < probabilities.length; state++) {
    cumulative += probabilities[state];
    if (u < cumulative) return state;
  }
  return probabilities.length - 1;
}
export function weightedSample(
  variables: Variable[],
  cpts: number[][][],
  cards: number[],
  order: number[],
  evidence: Map<number, number>,
  random: Minstd,
): { assignment: number[]; weight: number } {
  const assignment = Array<number>(variables.length).fill(0);
  let weight = 1;
  for (const v of order) {
    const row = cpts[v][combination(variables[v].parents, assignment, cards)];
    const observed = evidence.get(v);
    if (observed !== undefined) {
      assignment[v] = observed;
      weight *= row[observed];
    } else assignment[v] = select(row, random);
  }
  return { assignment, weight };
}

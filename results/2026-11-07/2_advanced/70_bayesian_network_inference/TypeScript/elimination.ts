import { at, product, removeVariable, scope, type Factor } from './factors.ts';
import type { Method } from './network_io.ts';

export interface Step {
  variable: number;
  fill: number;
  variables: number[];
  size: number;
}
export interface Plan {
  steps: Step[];
  maximum: number;
  total: number;
}
export function plan(
  factors: Factor[],
  eliminate: number[],
  method: Method,
  order: number[],
  cards: number[],
): Plan {
  const graph = new Map<number, Set<number>>();
  for (const factor of factors) {
    for (const v of factor.variables) {
      if (!graph.has(v)) graph.set(v, new Set());
      for (const u of factor.variables) if (u !== v) graph.get(v)!.add(u);
    }
  }
  const remaining = new Set(eliminate);
  const steps: Step[] = [];
  let maximum = 0;
  let total = 0;
  const candidate = (v: number) => {
    const neighbors = [...graph.get(v)!].sort((a, b) => a - b);
    let fill = 0;
    neighbors.forEach((u, i) => {
      for (const w of neighbors.slice(i + 1)) if (!graph.get(u)!.has(w)) fill++;
    });
    return { v, neighbors, fill };
  };
  while (remaining.size) {
    const candidates = [...remaining].map(candidate);
    candidates.sort((a, b) =>
      method === 'GIVEN'
        ? order.indexOf(a.v) - order.indexOf(b.v)
        : a.fill - b.fill || a.neighbors.length - b.neighbors.length || a.v - b.v,
    );
    const { v, neighbors, fill } = candidates[0];
    const variables = scope([v, ...neighbors]);
    let size = 1;
    for (const variable of variables) size *= cards[variable];
    steps.push({ variable: v, fill, variables, size });
    maximum = Math.max(maximum, size);
    total += size;
    for (const u of neighbors) {
      for (const w of neighbors) if (u !== w) graph.get(u)!.add(w);
      graph.get(u)!.delete(v);
    }
    graph.delete(v);
    remaining.delete(v);
  }
  return { steps, maximum, total };
}
export function eliminate(
  initial: Factor[],
  plan: Plan,
  cards: number[],
  maximize = false,
): { factor: Factor; products: Factor[] } {
  let factors = [...initial];
  const products: Factor[] = [];
  for (const step of plan.steps) {
    const selected = factors.filter((factor) => factor.variables.includes(step.variable));
    factors = factors.filter((factor) => !factor.variables.includes(step.variable));
    const combined = product(selected, cards);
    products.push(combined);
    factors.push(removeVariable(combined, step.variable, cards, maximize));
  }
  return { factor: product(factors, cards), products };
}
export function traceback(
  products: Factor[],
  plan: Plan,
  evidence: Map<number, number>,
  cards: number[],
): number[] {
  const assignment = Array<number>(cards.length).fill(0);
  for (const [v, state] of evidence) assignment[v] = state;
  for (let i = plan.steps.length - 1; i >= 0; i--) {
    const v = plan.steps[i].variable;
    let best = -Infinity;
    let chosen = 0;
    for (let state = 0; state < cards[v]; state++) {
      assignment[v] = state;
      const value = at(products[i], assignment, cards);
      if (value > best) {
        best = value;
        chosen = state;
      }
    }
    assignment[v] = chosen;
  }
  return assignment;
}

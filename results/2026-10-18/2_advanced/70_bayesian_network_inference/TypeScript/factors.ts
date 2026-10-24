import { combination } from './learning.ts';

export interface Factor {
  variables: number[];
  values: number[];
}
export function* assignments(variables: number[], cards: number[]): Generator<number[]> {
  const assignment = Array<number>(cards.length).fill(0);
  while (true) {
    yield [...assignment];
    let i = variables.length - 1;
    while (i >= 0) {
      const v = variables[i];
      assignment[v]++;
      if (assignment[v] < cards[v]) break;
      assignment[v] = 0;
      i--;
    }
    if (i < 0) return;
  }
}
export const scope = (variables: number[]) => [...new Set(variables)].sort((a, b) => a - b);
export function cptFactor(v: number, parents: number[], cpt: number[][], cards: number[]): Factor {
  const variables = scope([v, ...parents]);
  return {
    variables,
    values: [...assignments(variables, cards)].map(
      (assignment) => cpt[combination(parents, assignment, cards)][assignment[v]],
    ),
  };
}
export const at = (factor: Factor, assignment: number[], cards: number[]) =>
  factor.values[combination(factor.variables, assignment, cards)];
export function reduce(factor: Factor, evidence: Map<number, number>, cards: number[]): Factor {
  const variables = factor.variables.filter((v) => !evidence.has(v));
  const values: number[] = [];
  for (const assignment of assignments(variables, cards)) {
    for (const [v, state] of evidence) assignment[v] = state;
    values.push(at(factor, assignment, cards));
  }
  return { variables, values };
}
export function product(factors: Factor[], cards: number[]): Factor {
  if (!factors.length) return { variables: [], values: [1] };
  let result = factors[0];
  for (const factor of factors.slice(1)) {
    const variables = scope([...result.variables, ...factor.variables]);
    const values: number[] = [];
    for (const assignment of assignments(variables, cards)) {
      values.push(at(result, assignment, cards) * at(factor, assignment, cards));
    }
    result = { variables, values };
  }
  return result;
}
export function removeVariable(
  factor: Factor,
  v: number,
  cards: number[],
  maximize: boolean,
): Factor {
  const variables = factor.variables.filter((variable) => variable !== v);
  const values: number[] = [];
  for (const assignment of assignments(variables, cards)) {
    let value = maximize ? -Infinity : 0;
    for (let state = 0; state < cards[v]; state++) {
      assignment[v] = state;
      const term = at(factor, assignment, cards);
      value = maximize ? Math.max(value, term) : value + term;
    }
    values.push(value);
  }
  return { variables, values };
}

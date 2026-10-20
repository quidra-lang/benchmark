export function combination(parents: number[], assignment: number[], cards: number[]): number {
  let row = 0; for (const parent of parents) row = row * cards[parent] + assignment[parent]; return row;
}
export function countFamily(v: number, parents: number[], cards: number[], samples: number[][]): number[][] {
  let rows = 1; for (const parent of parents) rows *= cards[parent];
  const counts = Array.from({ length: rows }, () => Array<number>(cards[v]).fill(0));
  for (const sample of samples) counts[combination(parents, sample, cards)][sample[v]]++;
  return counts;
}
export function learn(counts: number[][], alpha: number): number[][] {
  return counts.map(row => { let total = 0; for (const count of row) total += count + alpha; return row.map(count => (count + alpha) / total); });
}
export function logLikelihood(counts: number[][], cpt: number[][]): number {
  let result = 0;
  counts.forEach((row, r) => row.forEach((count, s) => { if (count) result += count * Math.log(cpt[r][s]); }));
  return result;
}
export const parameters = (counts: number[][]) => (counts[0].length - 1) * counts.length;
export function familyScore(v: number, parents: number[], cards: number[], samples: number[][], alpha: number): number {
  const counts = countFamily(v, [...parents].sort((a, b) => a - b), cards, samples);
  return logLikelihood(counts, learn(counts, alpha)) - parameters(counts) * Math.log(samples.length) / 2;
}

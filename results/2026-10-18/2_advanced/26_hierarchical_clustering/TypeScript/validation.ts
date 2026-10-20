import type { Matrix } from './distances.ts';
export type Fraction = [number, number];

export function correlation(first: number[], second: number[]): number {
  let sx = 0;
  let sy = 0;
  for (let i = 0; i < first.length; i++) {
    sx += first[i];
    sy += second[i];
  }
  const mx = sx / first.length;
  const my = sy / first.length;
  let xy = 0;
  let xx = 0;
  let yy = 0;
  for (let i = 0; i < first.length; i++) {
    const x = first[i] - mx;
    const y = second[i] - my;
    xy += x * y;
    xx += x * x;
    yy += y * y;
  }
  return xy / Math.sqrt(xx * yy);
}

export function contingency(
  first: number[],
  second: number[],
  rows = Math.max(...first) + 1,
  columns = Math.max(...second) + 1,
): Matrix {
  const table = Array.from({ length: rows }, () => Array<number>(columns).fill(0));
  for (let i = 0; i < first.length; i++) table[first[i]][second[i]]++;
  return table;
}

export function adjustedRand(first: number[], second: number[]): Fraction {
  const table = contingency(first, second);
  const columns = table[0].map(() => 0);
  const chooseTwo = (n: number) => (n * (n - 1)) / 2;
  let cells = 0;
  let rows = 0;
  for (const row of table) {
    let total = 0;
    row.forEach((value, column) => {
      cells += chooseTwo(value);
      total += value;
      columns[column] += value;
    });
    rows += chooseTwo(total);
  }
  let columnPairs = 0;
  for (const total of columns) columnPairs += chooseTwo(total);
  const pairs = chooseTwo(first.length);
  let numerator = 2 * (pairs * cells - rows * columnPairs);
  let denominator = pairs * (rows + columnPairs) - 2 * rows * columnPairs;
  if (denominator === 0) return [1, 1];
  if (denominator < 0) {
    numerator = -numerator;
    denominator = -denominator;
  }
  let a = Math.abs(numerator);
  let b = denominator;
  while (b !== 0) [a, b] = [b, a % b];
  return [numerator / a, denominator / a];
}

export function silhouettes(matrix: Matrix, partition: number[]): number[] | null {
  const count = Math.max(...partition) + 1;
  if (count === 1) return null;
  const groups = Array.from({ length: count }, (): number[] => []);
  partition.forEach((cluster, observation) => groups[cluster].push(observation));
  return partition.map((cluster, observation) => {
    if (groups[cluster].length === 1) return 0;
    let within = 0;
    for (const other of groups[cluster]) {
      if (other !== observation) within += matrix[observation][other];
    }
    const a = within / (groups[cluster].length - 1);
    let b = Infinity;
    for (let other = 0; other < count; other++) {
      if (other === cluster) continue;
      let total = 0;
      for (const member of groups[other]) total += matrix[observation][member];
      b = Math.min(b, total / groups[other].length);
    }
    return (b - a) / Math.max(a, b);
  });
}

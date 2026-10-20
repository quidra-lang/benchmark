import type { Row } from './dataset.ts';
export type Fraction = [number, number];
export function fraction(a: number, b: number): Fraction | null {
  if (!b) return null;
  let x = Math.abs(a);
  let y = b;
  while (y) [x, y] = [y, x % y];
  return [a / x, b / x];
}
export const addFractions = (a: Fraction, b: Fraction) =>
  fraction(a[0] * b[1] + b[0] * a[1], a[1] * b[1])!;
export function confusion(rows: Row[], predicted: number[], count: number) {
  const table: number[][] = Array.from({ length: count }, () => Array(count).fill(0));
  rows.forEach((r, i) => table[r.class][predicted[i]]++);
  const support: number[] = Array(count).fill(0);
  const decided: number[] = Array(count).fill(0);
  let correct = 0;
  for (let a = 0; a < count; a++) {
    for (let b = 0; b < count; b++) {
      support[a] += table[a][b];
      decided[b] += table[a][b];
    }
    correct += table[a][a];
  }
  const classes: { support: number; recall: Fraction; precision: Fraction | null; f1: Fraction }[] =
    [];
  let recalls: Fraction = [0, 1];
  let macro = 0;
  let expected = 0;
  for (let k = 0; k < count; k++) {
    const tp = table[k][k];
    const recall = fraction(tp, support[k])!;
    classes.push({
      support: support[k],
      recall,
      precision: fraction(tp, decided[k]),
      f1: fraction(2 * tp, support[k] + decided[k])!,
    });
    recalls = addFractions(recalls, recall);
    macro += (2 * tp) / (support[k] + decided[k]);
    expected += support[k] * decided[k];
  }
  const n = rows.length;
  return {
    table,
    classes,
    correct,
    accuracy: fraction(correct, n),
    balanced: fraction(recalls[0], recalls[1] * count),
    kappa: fraction(n * correct - expected, n * n - expected),
    macroF1: macro / count,
  };
}
export function mcnemar(rows: Row[], a: number[], b: number[]) {
  let b01 = 0;
  let b10 = 0;
  rows.forEach((r, i) => {
    if (a[i] === r.class && b[i] !== r.class) b01++;
    else if (a[i] !== r.class && b[i] === r.class) b10++;
  });
  const d = Math.abs(b01 - b10) - 1;
  const chi2 = b01 === b10 ? 0 : (d * d) / (b01 + b10);
  return { b01, b10, chi2, significant: chi2 > 3.841 };
}
export class Random {
  constructor(public state: number) {}
  next() {
    this.state = (48271 * this.state) % 2147483647;
    return this.state;
  }
}
